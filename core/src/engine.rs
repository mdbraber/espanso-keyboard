//! The expansion engine: typed characters in, expansions out.
//!
//! This is the keyboard's version of Espanso's desktop pipeline (the middleware in
//! `espanso-engine/src/process/middleware/`), reduced to what a keyboard needs: matcher,
//! cause compensation, render, cursor hint and undo. Each step notes the Espanso
//! middleware it follows.

use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::Result;
use espanso_config::matches::{Match, MatchCause, MatchEffect, TextFormat};
use espanso_match::event::{Event, Key};
use espanso_match::regex::{RegexMatcher, RegexMatcherOptions, RegexMatcherState};
use espanso_match::rolling::matcher::{RollingMatcher, RollingMatcherOptions, RollingMatcherState};
use espanso_match::{MatchResult, Matcher};
use espanso_render::extension::choice::ChoiceExtension;
use espanso_render::extension::clipboard::{ClipboardExtension, ClipboardProvider};
use espanso_render::extension::date::{DateExtension, DefaultLocaleProvider};
use espanso_render::extension::echo::EchoExtension;
use espanso_render::extension::form::FormExtension;
use espanso_render::extension::random::RandomExtension;
use espanso_render::{Context, RenderOptions, RenderResult, Renderer, Template, Variable};
use self_cell::self_cell;
use unicode_segmentation::UnicodeSegmentation;

use crate::espanso;
use crate::prompt::{Answer, Prompt, Prompter};
use crate::script::{ScriptExtension, ScriptRunner};

/// What the keyboard does to the text field for one expansion, or for undoing one.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Expansion {
    /// Characters (grapheme clusters, one `deleteBackward` each) to delete before the cursor.
    pub delete_count: u32,
    /// Text to insert after deleting.
    pub insert: String,
    /// Characters (grapheme clusters) to move the cursor left after inserting; 0 if none.
    pub cursor_offset: u32,
    /// The snippet's first trigger (or its regex), for usage counts; empty for an undo.
    pub snippet: String,
}

/// One snippet, for searching and listing.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SnippetSummary {
    /// Valid until the folder is loaded again.
    pub id: i32,
    /// Its triggers, or its regex for a regex trigger.
    pub triggers: Vec<String>,
    pub is_regex: bool,
    /// The match's label, or its replacement text when it has none (Espanso's
    /// `Match::description`).
    pub label: String,
    /// The replacement text as written, with `{{variables}}`.
    pub replace: String,
    /// The names of its variables, in order.
    pub vars: Vec<String>,
    /// The match file it comes from, relative to `match/`, such as `base.yml`. Matches
    /// imported into a file count as that file's.
    pub file: String,
}

/// A snippet whose trigger the text before the caret begins (plan step 6, suggestions).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct Completion {
    pub id: i32,
    pub trigger: String,
    /// How many characters (grapheme clusters) of the trigger are already typed: what
    /// accepting the completion replaces.
    pub typed: u32,
    pub label: String,
}

/// The clipboard, for `clipboard` variables; supplied by the host.
pub trait ClipboardReader: Send + Sync {
    fn text(&self) -> Option<String>;
}

/// An expansion on its way: rendered, or waiting for the answers to its questions.
struct Pending {
    id: i32,
    /// The trigger as typed, for `propagate_case`.
    trigger: String,
    /// A regex trigger's named groups.
    trigger_vars: HashMap<String, String>,
    right_separator: Option<String>,
    /// Characters to delete before inserting: the typed trigger, or a completion's start.
    delete: u32,
    /// Text typed in the same key press after the trigger.
    rest: String,
    /// What undo puts back, when undo is possible.
    undo_trigger: Option<String>,
    /// From typing: the matchers then see the expansion as a word separator.
    from_typing: bool,
    answers: Vec<Answer>,
}

enum Rendered {
    Done(String),
    Ask(Prompt),
    Cancelled,
}

/// Espanso's two matchers, which see every key (espanso/src/cli/worker/engine/mod.rs).
struct Matchers {
    rolling: RollingMatcher<i32>,
    regex: RegexMatcher<i32>,
}

/// The matchers' states after each recent key, newest last.
type History<'a> = VecDeque<(RollingMatcherState<'a, i32>, RegexMatcherState)>;

self_cell!(
    /// The matchers and Espanso's matcher state history, which borrows from them.
    struct MatcherCell {
        owner: Matchers,
        #[covariant]
        dependent: History,
    }
);

/// What undo needs after an expansion (`espanso-engine/.../undo.rs`, `InjectionRecord`).
struct UndoRecord {
    trigger: String,
    inserted: String,
}

/// Espanso snippet expansion for one keyboard.
///
/// The keyboard inserts each typed character into the text field first and then calls
/// [`type_text`](Self::type_text), as Espanso sees keys after they are typed. For
/// backspace it calls [`backspace`](Self::backspace) *before* deleting: if that returns an
/// expansion, the keyboard applies it instead of deleting a character.
pub struct EspansoEngine {
    matcher: MatcherCell,
    /// Active matches by id.
    matches: HashMap<i32, Match>,
    /// Templates of all active text matches, for nested matches.
    templates: Vec<Template>,
    template_index: HashMap<i32, usize>,
    global_vars: Vec<Variable>,
    undo_enabled: bool,
    max_history_size: usize,
    undo: Option<UndoRecord>,
    warnings: Vec<String>,
    last_error: Option<String>,
    config_folder: PathBuf,
    script_runner: Arc<dyn ScriptRunner>,
    clipboard: Option<Arc<dyn ClipboardReader>>,
    /// The match file of each match.
    files: HashMap<i32, String>,
    /// An expansion waiting for an answer, and its question.
    pending: Option<Pending>,
    prompt: Option<Prompt>,
}

impl EspansoEngine {
    /// Loads an Espanso folder (the one containing `config/` and `match/`) using the
    /// default configuration. App-specific configurations are ignored: a keyboard can't
    /// see which app it is in. `script_runner` runs the `.js` files of `script` variables.
    pub fn new(config_folder: &Path, script_runner: Arc<dyn ScriptRunner>) -> Result<Self> {
        let (config_store, match_store, non_fatal_errors) = espanso_config::load(config_folder)?;
        let config = config_store.default();
        let set = match_store.query(config.match_paths());

        let mut warnings: Vec<String> = non_fatal_errors
            .iter()
            .flat_map(|set| {
                set.errors
                    .iter()
                    .map(move |e| format!("{}: {:#}", set.file.display(), e.error))
            })
            .collect();

        let mut matches = HashMap::new();
        let mut templates = Vec::new();
        let mut template_index = HashMap::new();
        for m in &set.matches {
            if let Some(warning) = unsupported(m) {
                warnings.push(warning);
            }
            // Espanso only logs a regex it can't compile, and leaves it out.
            if let MatchCause::Regex(cause) = &m.cause {
                if let Err(err) = regex::Regex::new(&cause.regex) {
                    warnings.push(format!("{}: invalid regex: {err}", cause.regex));
                }
            }
            if let Some(template) = espanso::convert_to_template(m) {
                template_index.insert(m.id, templates.len());
                templates.push(template);
            }
            matches.insert(m.id, (*m).clone());
        }

        // Which file each match comes from: query the files one by one.
        let mut files = HashMap::new();
        for path in config.match_paths() {
            let name = match_file_name(path);
            for m in match_store.query(std::slice::from_ref(path)).matches {
                files.entry(m.id).or_insert_with(|| name.clone());
            }
        }

        let global_vars = set
            .global_vars
            .iter()
            .map(|v| espanso::convert_var((*v).clone()))
            .collect();

        // From espanso/src/cli/worker/engine/process/middleware/matcher/rolling.rs and
        // regex.rs.
        let rolling = RollingMatcher::new(
            &espanso::rolling_matches(&set.matches),
            RollingMatcherOptions {
                char_word_separators: config.word_separators(),
                key_word_separators: vec![],
            },
        );
        let regex = RegexMatcher::new(
            &espanso::regex_matches(&set.matches),
            RegexMatcherOptions {
                max_buffer_size: config.max_regex_buffer_size(),
            },
        );

        Ok(Self {
            matcher: MatcherCell::new(Matchers { rolling, regex }, |_| VecDeque::new()),
            matches,
            templates,
            template_index,
            global_vars,
            undo_enabled: config.undo_backspace(),
            max_history_size: config.backspace_limit(),
            undo: None,
            warnings,
            last_error: None,
            config_folder: config_folder.to_owned(),
            script_runner,
            clipboard: None,
            files,
            pending: None,
            prompt: None,
        })
    }

    /// One key press: a character, or `"\n"` for return. Call after the keyboard has
    /// inserted it. Returns an expansion when it completes a trigger.
    pub fn type_text(&mut self, text: &str) -> Option<Expansion> {
        // Any key other than backspace ends the chance to undo (undo.rs), and drops a
        // question left unanswered.
        self.undo = None;
        self.cancel_prompt();

        let mut expansion = None;
        // Espanso's matcher compares one Unicode scalar per event (RollingMatch::from_string).
        for (index, c) in text.char_indices() {
            let results = self.feed(Event::Key {
                key: Key::Other,
                chars: Some(c.to_string()),
            });
            // A key press inserting several characters (such as ".com") could complete a
            // trigger before its end. The rest is already in the text field after the
            // trigger, so it is deleted and inserted again after the expansion. Only the
            // first expansion in one key press is applied.
            if expansion.is_none() {
                if let Some(result) = results.into_iter().next() {
                    let rest = &text[index + c.len_utf8()..];
                    expansion = self.expand(result, rest);
                }
            }
        }
        expansion
    }

    /// Backspace. Call before the keyboard deletes anything. Returns an expansion that
    /// undoes the last expansion when `undo_backspace` is on and nothing was typed since;
    /// the keyboard then applies it instead of deleting a character.
    pub fn backspace(&mut self) -> Option<Expansion> {
        self.cancel_prompt();
        // matcher.rs: backspace steps the matcher back one key.
        self.matcher.with_dependent_mut(|_, history| {
            history.pop_back();
        });

        // undo.rs and action.rs. Espanso deletes one character fewer because the
        // backspace has already deleted one; here the keyboard's own delete is skipped.
        let record = self.undo.take()?;
        if !self.undo_enabled {
            return None;
        }
        Some(Expansion {
            delete_count: graphemes(&record.inserted),
            insert: record.trigger,
            cursor_offset: 0,
            snippet: String::new(),
        })
    }

    /// Forgets what was typed: the cursor moved, the field changed or the keyboard
    /// reappeared. Espanso does the same for a mouse click (matcher.rs, undo.rs).
    pub fn reset(&mut self) {
        self.matcher
            .with_dependent_mut(|_, history| history.clear());
        self.undo = None;
        self.cancel_prompt();
    }

    /// The clipboard for `clipboard` variables; without one they fail.
    pub fn set_clipboard(&mut self, clipboard: Arc<dyn ClipboardReader>) {
        self.clipboard = Some(clipboard);
    }

    /// The question the last trigger asks before it can expand (a `choice` or `form`
    /// variable), if any. [`answer`](Self::answer) it, or type on to drop it.
    pub fn prompt(&self) -> Option<&Prompt> {
        self.prompt.as_ref()
    }

    /// Answers the question from [`prompt`](Self::prompt). Returns the expansion, or
    /// `None` when the snippet asks another question (see `prompt` again) or failed.
    pub fn answer(&mut self, answer: Answer) -> Option<Expansion> {
        let mut pending = self.pending.take()?;
        self.prompt = None;
        pending.answers.push(answer);
        self.produce(pending)
    }

    /// Drops the question from [`prompt`](Self::prompt) without expanding.
    pub fn cancel_prompt(&mut self) {
        self.pending = None;
        self.prompt = None;
    }

    /// Expands the snippet `id` at the caret, after deleting `delete_count` characters:
    /// a snippet picked from a list, or a completion (then `delete_count` is its
    /// `typed`). Like a trigger, it may ask a question first.
    pub fn insert_snippet(&mut self, id: i32, delete_count: u32) -> Option<Expansion> {
        self.reset();
        let trigger = self.snippet_key(id);
        self.produce(Pending {
            id,
            trigger,
            trigger_vars: HashMap::new(),
            right_separator: None,
            delete: delete_count,
            rest: String::new(),
            undo_trigger: None,
            from_typing: false,
            answers: Vec::new(),
        })
    }

    /// What the snippet `id` expands to now, with questions answered by their defaults
    /// (the first choice, the fields' defaults) and without the `$|$` marker.
    pub fn preview(&self, id: i32) -> Result<String> {
        let pending = Pending {
            id,
            trigger: self.snippet_key(id),
            trigger_vars: HashMap::new(),
            right_separator: None,
            delete: 0,
            rest: String::new(),
            undo_trigger: None,
            from_typing: false,
            answers: Vec::new(),
        };
        match self.render(&pending, true)? {
            Rendered::Done(body) => Ok(espanso::process_cursor_hint(body).0),
            Rendered::Ask(_) | Rendered::Cancelled => anyhow::bail!("the snippet was cancelled"),
        }
    }

    /// What the regex snippet `id` expands to for `typed`, an example of its trigger: the
    /// regex's named groups come from it, as when typing. Questions take their defaults.
    pub fn preview_typed(&self, id: i32, typed: &str) -> Result<String> {
        let Some(MatchCause::Regex(cause)) = self.matches.get(&id).map(|m| &m.cause) else {
            return self.preview(id);
        };
        let regex = regex::Regex::new(&cause.regex)?;
        let captures = regex
            .captures(typed)
            .ok_or_else(|| anyhow::anyhow!("{typed} doesn't match {}", cause.regex))?;
        let trigger_vars = regex
            .capture_names()
            .flatten()
            .filter_map(|name| Some((name.to_string(), captures.name(name)?.as_str().to_string())))
            .collect();
        let pending = Pending {
            id,
            trigger: typed.to_string(),
            trigger_vars,
            right_separator: None,
            delete: 0,
            rest: String::new(),
            undo_trigger: None,
            from_typing: false,
            answers: Vec::new(),
        };
        match self.render(&pending, true)? {
            Rendered::Done(body) => Ok(espanso::process_cursor_hint(body).0),
            Rendered::Ask(_) | Rendered::Cancelled => anyhow::bail!("the snippet was cancelled"),
        }
    }

    /// Snippets whose trigger the text before the caret has begun: the longest typed
    /// start first. A trigger starting with a letter needs three characters at the
    /// start of a word, so ordinary words don't keep suggesting snippets; others, such
    /// as `;jitsi`, need two.
    pub fn complete(&self, before: &str) -> Vec<Completion> {
        let mut completions = Vec::new();
        for (id, m) in &self.matches {
            let MatchCause::Trigger(cause) = &m.cause else {
                continue;
            };
            if unsupported(m).is_some() {
                continue;
            }
            for trigger in &cause.triggers {
                if let Some(typed) = typed_start(before, trigger, cause.propagate_case) {
                    completions.push(Completion {
                        id: *id,
                        trigger: trigger.clone(),
                        typed,
                        label: m.description().to_string(),
                    });
                }
            }
        }
        completions.sort_by(|a, b| {
            b.typed
                .cmp(&a.typed)
                .then_with(|| a.trigger.cmp(&b.trigger))
        });
        completions
    }

    /// Snippets the keyboard can expand whose trigger, label or search terms contain
    /// `query` (ignoring case). An empty query lists all of them.
    pub fn search(&self, query: &str) -> Vec<SnippetSummary> {
        let query = query.to_lowercase();
        let mut matches: Vec<&Match> = self.matches.values().collect();
        matches.sort_by_key(|m| m.id);
        matches
            .into_iter()
            .filter(|m| !matches!(m.cause, MatchCause::None) && unsupported(m).is_none())
            .filter(|m| {
                query.is_empty()
                    || m.description().to_lowercase().contains(&query)
                    || m.search_terms()
                        .iter()
                        .any(|t| t.to_lowercase().contains(&query))
            })
            .map(|m| {
                let (replace, vars) = match &m.effect {
                    MatchEffect::Text(text) => (
                        text.replace.clone(),
                        text.vars.iter().map(|v| v.name.clone()).collect(),
                    ),
                    _ => (String::new(), Vec::new()),
                };
                SnippetSummary {
                    id: m.id,
                    triggers: match &m.cause {
                        MatchCause::Regex(cause) => vec![cause.regex.clone()],
                        cause => cause.search_terms().iter().map(|t| t.to_string()).collect(),
                    },
                    is_regex: matches!(m.cause, MatchCause::Regex(_)),
                    label: m.description().to_string(),
                    replace,
                    vars,
                    file: self.files.get(&m.id).cloned().unwrap_or_default(),
                }
            })
            .collect()
    }

    /// Problems found while loading, one per line, including snippets the keyboard can't
    /// expand.
    pub fn warnings(&self) -> &[String] {
        &self.warnings
    }

    /// Why the last completed trigger didn't expand, if it didn't.
    pub fn last_error(&self) -> Option<&str> {
        self.last_error.as_deref()
    }

    /// matcher.rs: feeds one event to both matchers and keeps up to `backspace_limit`
    /// states for backspace. Trigger matches come before regex matches, as in Espanso.
    fn feed(&mut self, event: Event) -> Vec<MatchResult<i32>> {
        let max_history_size = self.max_history_size;
        self.matcher.with_dependent_mut(|matchers, history| {
            let previous = history.back();
            let (rolling, mut results) = matchers
                .rolling
                .process(previous.map(|s| &s.0), event.clone());
            let (regex, regex_results) = matchers.regex.process(previous.map(|s| &s.1), event);
            results.extend(regex_results);
            history.push_back((rolling, regex));
            if history.len() > max_history_size {
                history.pop_front();
            }
            results
        })
    }

    /// From a detected trigger to an expansion, as Espanso's cause compensation
    /// middleware prepares it. `rest` is text typed in the same key press after the
    /// trigger.
    fn expand(&mut self, result: MatchResult<i32>, rest: &str) -> Option<Expansion> {
        // Several matches with the same trigger: Espanso asks which one; the keyboard has
        // no picker yet and takes the first.

        // action.rs (TriggerCompensation): delete the trigger but keep the left separator.
        let typed = match &result.left_separator {
            Some(separator) => result
                .trigger
                .strip_prefix(separator.as_str())
                .unwrap_or(&result.trigger),
            None => &result.trigger,
        }
        .to_string();

        self.produce(Pending {
            id: result.id,
            delete: graphemes(&typed) + graphemes(rest),
            // undo.rs. Unlike Espanso, undo puts back only what was deleted: Espanso
            // re-types the left separator too, doubling it (docs/decisions.md, "Undo
            // restores only the deleted text").
            undo_trigger: rest.is_empty().then(|| typed.clone()),
            trigger: result.trigger,
            trigger_vars: result.vars,
            right_separator: result.right_separator,
            rest: rest.to_string(),
            from_typing: true,
            answers: Vec::new(),
        })
    }

    /// Renders a pending expansion and turns it into an expansion: render, cursor hint
    /// and undo record, as in Espanso's middleware of those names. A question leaves it
    /// pending (see `prompt`).
    fn produce(&mut self, pending: Pending) -> Option<Expansion> {
        self.last_error = None;
        let body = match self.render(&pending, false) {
            Ok(Rendered::Done(body)) => body,
            Ok(Rendered::Ask(prompt)) => {
                self.prompt = Some(prompt);
                self.pending = Some(pending);
                return None;
            }
            Ok(Rendered::Cancelled) => return None,
            Err(err) => {
                self.last_error = Some(format!("{}: {err:#}", pending.trigger));
                return None;
            }
        };

        // render.rs: the right separator is typed again after the replacement.
        let body = match &pending.right_separator {
            Some(separator) => format!("{body}{separator}"),
            None => body,
        };
        let (body, cursor_hint) = espanso::process_cursor_hint(body);
        let rest = &pending.rest;

        let expansion = Expansion {
            delete_count: pending.delete,
            insert: format!("{body}{rest}"),
            cursor_offset: cursor_hint.map_or(0, |moves| moves as u32 + graphemes(rest)),
            snippet: self.snippet_key(pending.id),
        };

        // matcher.rs: the injected match acts as a word separator.
        if pending.from_typing {
            self.feed(Event::VirtualSeparator);
        }

        // undo.rs: a cursor hint disables undo.
        if let (None, Some(trigger)) = (cursor_hint, pending.undo_trigger) {
            self.undo = Some(UndoRecord {
                trigger,
                inserted: body,
            });
        }

        Some(expansion)
    }

    /// A snippet's first trigger, or its regex.
    fn snippet_key(&self, id: i32) -> String {
        match self.matches.get(&id).map(|m| &m.cause) {
            Some(MatchCause::Trigger(cause)) => cause.triggers.first().cloned().unwrap_or_default(),
            Some(MatchCause::Regex(cause)) => cause.regex.clone(),
            _ => String::new(),
        }
    }

    /// render/mod.rs (`RendererAdapter::render`), with the pending expansion's answers.
    /// `use_defaults` answers questions with their defaults instead of asking.
    fn render(&self, pending: &Pending, use_defaults: bool) -> Result<Rendered> {
        let id = pending.id;
        let m = self
            .matches
            .get(&id)
            .ok_or_else(|| anyhow::anyhow!("match not found"))?;
        if let Some(warning) = unsupported(m) {
            anyhow::bail!(warning);
        }
        let template = self
            .template_index
            .get(&id)
            .map(|&i| &self.templates[i])
            .ok_or_else(|| anyhow::anyhow!("match has no text"))?;

        // Extensions as in espanso/src/cli/worker/engine/mod.rs, minus `shell`, which
        // needs the desktop, so `shell` variables fail.
        let locale_provider = DefaultLocaleProvider::new();
        let date = DateExtension::new(&locale_provider);
        let echo = EchoExtension::new();
        let random = RandomExtension::new();
        let script = ScriptExtension::new(&self.config_folder, &*self.script_runner);
        let prompter = Prompter::new(&pending.answers, use_defaults);
        let choice = ChoiceExtension::new(&prompter);
        let form = FormExtension::new(&prompter);
        let clipboard_reader = ClipboardAdapter(self.clipboard.as_deref());
        let clipboard = ClipboardExtension::new(&clipboard_reader);
        let renderer = espanso_render::create(vec![
            &clipboard, &date, &echo, &random, &script, &form, &choice,
        ]);

        let context = Context {
            global_vars: self.global_vars.iter().collect(),
            templates: self.templates.iter().collect(),
        };
        let options = RenderOptions {
            casing_style: espanso::casing_style(m, &pending.trigger),
        };

        let augmented = espanso::augment_template(template, pending.trigger_vars.clone());
        let template = augmented.as_ref().unwrap_or(template);

        match renderer.render(template, &context, &options) {
            RenderResult::Success(body) => Ok(Rendered::Done(body)),
            RenderResult::Aborted => Ok(match prompter.asked.take() {
                Some(prompt) => Rendered::Ask(prompt),
                None => Rendered::Cancelled,
            }),
            RenderResult::Error(err) => Err(err),
        }
    }
}

/// Why the keyboard can't expand a match, if it can't.
fn unsupported(m: &Match) -> Option<String> {
    let what = match &m.effect {
        MatchEffect::Text(text) => match text.format {
            TextFormat::Plain => return None,
            TextFormat::Markdown => "markdown",
            TextFormat::Html => "html",
        },
        MatchEffect::Image(_) => "image",
        MatchEffect::None => return None,
    };
    let name = m.cause.description().unwrap_or("(no trigger)");
    Some(format!(
        "{name}: {what} snippets can't be typed by a keyboard"
    ))
}

struct ClipboardAdapter<'a>(Option<&'a dyn ClipboardReader>);

impl ClipboardProvider for ClipboardAdapter<'_> {
    fn get_text(&self) -> Option<String> {
        self.0.and_then(|reader| reader.text())
    }
}

/// A match file's name relative to `match/`, from one of the configuration's match
/// paths.
fn match_file_name(path: &str) -> String {
    let path = Path::new(path);
    let components: Vec<_> = path.components().collect();
    match components.iter().rposition(|c| c.as_os_str() == "match") {
        Some(i) => components[i + 1..]
            .iter()
            .map(|c| c.as_os_str().to_string_lossy())
            .collect::<Vec<_>>()
            .join("/"),
        None => path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default(),
    }
}

/// How many characters of `trigger` end `before`, if it's a start worth completing:
/// shorter than the whole trigger, at least two characters, or three at the start of a
/// word for a trigger starting with a letter.
fn typed_start(before: &str, trigger: &str, ignore_case: bool) -> Option<u32> {
    let trigger_chars: Vec<char> = trigger.chars().collect();
    let starts_with_letter = trigger_chars.first().is_some_and(|c| c.is_alphanumeric());
    let minimum = if starts_with_letter { 3 } else { 2 };
    let before_chars: Vec<char> = before.chars().collect();
    let same = |a: char, b: char| a == b || (ignore_case && a.to_lowercase().eq(b.to_lowercase()));
    for length in (minimum..trigger_chars.len()).rev() {
        if length > before_chars.len() {
            continue;
        }
        let tail = &before_chars[before_chars.len() - length..];
        if !tail
            .iter()
            .zip(&trigger_chars[..length])
            .all(|(a, b)| same(*a, *b))
        {
            continue;
        }
        let preceding = before_chars
            .len()
            .checked_sub(length + 1)
            .map(|i| before_chars[i]);
        if starts_with_letter && preceding.is_some_and(|c| c.is_alphanumeric()) {
            continue;
        }
        return Some(graphemes(&tail.iter().collect::<String>()));
    }
    None
}

fn graphemes(text: &str) -> u32 {
    text.graphemes(true).count() as u32
}
