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
use espanso_render::extension::choice::{
    Choice, ChoiceExtension, ChoiceSelector, ChoiceSelectorResult,
};
use espanso_render::extension::date::{DateExtension, DefaultLocaleProvider};
use espanso_render::extension::echo::EchoExtension;
use espanso_render::extension::random::RandomExtension;
use espanso_render::{Context, RenderOptions, RenderResult, Renderer, Template, Variable};
use self_cell::self_cell;
use unicode_segmentation::UnicodeSegmentation;

use crate::espanso;
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
}

/// One snippet, for searching and listing.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SnippetSummary {
    pub triggers: Vec<String>,
    /// The match's label, or its replacement text when it has none (Espanso's
    /// `Match::description`).
    pub label: String,
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
        })
    }

    /// One key press: a character, or `"\n"` for return. Call after the keyboard has
    /// inserted it. Returns an expansion when it completes a trigger.
    pub fn type_text(&mut self, text: &str) -> Option<Expansion> {
        // Any key other than backspace ends the chance to undo (undo.rs).
        self.undo = None;

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
        })
    }

    /// Forgets what was typed: the cursor moved, the field changed or the keyboard
    /// reappeared. Espanso does the same for a mouse click (matcher.rs, undo.rs).
    pub fn reset(&mut self) {
        self.matcher
            .with_dependent_mut(|_, history| history.clear());
        self.undo = None;
    }

    /// Snippets whose trigger, label or search terms contain `query` (ignoring case).
    /// An empty query lists every snippet.
    pub fn search(&self, query: &str) -> Vec<SnippetSummary> {
        let query = query.to_lowercase();
        let mut matches: Vec<&Match> = self.matches.values().collect();
        matches.sort_by_key(|m| m.id);
        matches
            .into_iter()
            .filter(|m| !matches!(m.cause, MatchCause::None))
            .filter(|m| {
                query.is_empty()
                    || m.description().to_lowercase().contains(&query)
                    || m.search_terms()
                        .iter()
                        .any(|t| t.to_lowercase().contains(&query))
            })
            .map(|m| SnippetSummary {
                triggers: match &m.cause {
                    MatchCause::Regex(cause) => vec![cause.regex.clone()],
                    cause => cause.search_terms().iter().map(|t| t.to_string()).collect(),
                },
                label: m.description().to_string(),
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

    /// From a detected trigger to an expansion: cause compensation, render, cursor hint
    /// and undo record, as in Espanso's middleware of those names. `rest` is text typed in
    /// the same key press after the trigger.
    fn expand(&mut self, result: MatchResult<i32>, rest: &str) -> Option<Expansion> {
        // Several matches with the same trigger: Espanso asks which one; the keyboard has
        // no picker yet and takes the first.
        self.last_error = None;
        let body = match self.render(result.id, &result.trigger, result.vars) {
            Ok(Some(body)) => body,
            Ok(None) => return None,
            Err(err) => {
                self.last_error = Some(format!("{}: {err:#}", result.trigger));
                return None;
            }
        };

        // render.rs: the right separator is typed again after the replacement.
        let body = match &result.right_separator {
            Some(separator) => format!("{body}{separator}"),
            None => body,
        };
        let (body, cursor_hint) = espanso::process_cursor_hint(body);

        // action.rs (TriggerCompensation): delete the trigger but keep the left separator.
        let typed = match &result.left_separator {
            Some(separator) => result
                .trigger
                .strip_prefix(separator.as_str())
                .unwrap_or(&result.trigger),
            None => &result.trigger,
        };

        let expansion = Expansion {
            delete_count: graphemes(typed) + graphemes(rest),
            insert: format!("{body}{rest}"),
            cursor_offset: cursor_hint.map_or(0, |moves| moves as u32 + graphemes(rest)),
        };

        // matcher.rs: the injected match acts as a word separator.
        self.feed(Event::VirtualSeparator);

        // undo.rs: a cursor hint disables undo. Unlike Espanso, undo puts back only what
        // was deleted: Espanso re-types the left separator too, doubling it
        // (docs/decisions.md, "Undo restores only the deleted text").
        if cursor_hint.is_none() && rest.is_empty() {
            self.undo = Some(UndoRecord {
                trigger: typed.to_string(),
                inserted: body,
            });
        }

        Some(expansion)
    }

    /// render/mod.rs (`RendererAdapter::render`). `trigger_vars` are a regex trigger's
    /// named groups. `Ok(None)` means the snippet was cancelled, for example a choice with
    /// nothing chosen.
    fn render(
        &self,
        id: i32,
        trigger: &str,
        trigger_vars: HashMap<String, String>,
    ) -> Result<Option<String>> {
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

        // Extensions as in espanso/src/cli/worker/engine/mod.rs, minus those that need the
        // desktop: no shell, so `shell` variables fail. Clipboard and choice pickers
        // arrive in plan step 6.
        let locale_provider = DefaultLocaleProvider::new();
        let date = DateExtension::new(&locale_provider);
        let echo = EchoExtension::new();
        let random = RandomExtension::new();
        let script = ScriptExtension::new(&self.config_folder, &*self.script_runner);
        let choice = ChoiceExtension::new(&NoChoiceSelector);
        let renderer = espanso_render::create(vec![&date, &echo, &random, &script, &choice]);

        let context = Context {
            global_vars: self.global_vars.iter().collect(),
            templates: self.templates.iter().collect(),
        };
        let options = RenderOptions {
            casing_style: espanso::casing_style(m, trigger),
        };

        let augmented = espanso::augment_template(template, trigger_vars);
        let template = augmented.as_ref().unwrap_or(template);

        match renderer.render(template, &context, &options) {
            RenderResult::Success(body) => Ok(Some(body)),
            RenderResult::Aborted => Ok(None),
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

/// The keyboard has no choice picker yet (plan step 6), so `choice` variables cancel the
/// snippet.
struct NoChoiceSelector;

impl ChoiceSelector for NoChoiceSelector {
    fn show(&self, _: &[Choice]) -> ChoiceSelectorResult {
        ChoiceSelectorResult::Aborted
    }
}

fn graphemes(text: &str) -> u32 {
    text.graphemes(true).count() as u32
}
