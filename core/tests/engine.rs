//! The expansion engine against fixtures/espanso/, through a simulated text field that
//! applies expansions the way the keyboard will (plan step 1).

use std::path::PathBuf;

use espanso_keyboard_core::{EspansoEngine, Expansion};
use unicode_segmentation::UnicodeSegmentation;

fn fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../fixtures/espanso")
}

fn engine() -> EspansoEngine {
    let engine = EspansoEngine::new(&fixture()).expect("fixture should load");
    assert!(
        engine.warnings().is_empty(),
        "warnings: {:?}",
        engine.warnings()
    );
    engine
}

/// A text field with the cursor at the end of `before`, edited the way the keyboard edits
/// through `textDocumentProxy`: one grapheme cluster per `deleteBackward`.
struct Field {
    engine: EspansoEngine,
    before: String,
    after: String,
    expansions: Vec<Expansion>,
}

impl Field {
    fn new() -> Self {
        Self {
            engine: engine(),
            before: String::new(),
            after: String::new(),
            expansions: Vec::new(),
        }
    }

    /// Types `text` one key press (grapheme cluster) at a time.
    fn type_keys(&mut self, text: &str) -> &mut Self {
        for key in text.graphemes(true) {
            self.before.push_str(key);
            if let Some(expansion) = self.engine.type_text(key) {
                self.apply(expansion);
            }
        }
        self
    }

    fn backspace(&mut self) -> &mut Self {
        match self.engine.backspace() {
            Some(expansion) => self.apply(expansion),
            None => self.delete_backward(1),
        }
        self
    }

    fn apply(&mut self, expansion: Expansion) {
        self.delete_backward(expansion.delete_count as usize);
        self.before.push_str(&expansion.insert);
        let mut moved: Vec<&str> = self.before.graphemes(true).collect();
        let split = moved.len() - expansion.cursor_offset as usize;
        let tail: String = moved.split_off(split).concat();
        self.before = moved.concat();
        self.after = tail + &self.after;
        self.expansions.push(expansion);
    }

    fn delete_backward(&mut self, count: usize) {
        let mut graphemes: Vec<&str> = self.before.graphemes(true).collect();
        assert!(
            count <= graphemes.len(),
            "deleting {count} from {:?}",
            self.before
        );
        graphemes.truncate(graphemes.len() - count);
        self.before = graphemes.concat();
    }

    fn text(&self) -> String {
        format!("{}|{}", self.before, self.after)
    }
}

#[test]
fn today_expands_to_the_date() {
    let today = chrono::Local::now().format("%Y-%m-%d").to_string();
    let mut field = Field::new();
    field.type_keys(";today");
    assert_eq!(field.text(), format!("{today}|"));
    assert_eq!(
        field.expansions[0],
        Expansion {
            delete_count: 6,
            insert: today,
            cursor_offset: 0
        }
    );
}

#[test]
fn word_trigger_fires_only_between_word_separators() {
    assert_eq!(Field::new().type_keys("brb ").text(), "be right back |");
    assert_eq!(
        Field::new().type_keys("ok brb.").text(),
        "ok be right back.|"
    );
    assert_eq!(Field::new().type_keys("abrb ").text(), "abrb |");
    assert_eq!(Field::new().type_keys("brbs ").text(), "brbs |");
    assert_eq!(Field::new().type_keys("brb").text(), "brb|");
}

#[test]
fn word_trigger_keeps_the_left_separator() {
    let mut field = Field::new();
    field.type_keys("ok brb ");
    // " brb " was matched; the leading space stays, "brb " is replaced.
    assert_eq!(field.expansions[0].delete_count, 4);
    assert_eq!(field.expansions[0].insert, "be right back ");
}

#[test]
fn cursor_hint_gives_the_cursor_offset() {
    let mut field = Field::new();
    field.type_keys(";dear");
    assert_eq!(
        field.expansions[0],
        Expansion {
            delete_count: 5,
            insert: "Dear ,".into(),
            cursor_offset: 1
        }
    );
    assert_eq!(field.text(), "Dear |,");
    field.type_keys("Anna");
    assert_eq!(field.text(), "Dear Anna|,");
}

#[test]
fn backspace_right_after_an_expansion_restores_the_trigger() {
    let mut field = Field::new();
    field.type_keys("x ;hi");
    assert_eq!(field.text(), "x Hoi daar|");
    field.backspace();
    assert_eq!(field.text(), "x ;hi|");
    assert_eq!(
        field.expansions[1],
        Expansion {
            delete_count: 8,
            insert: ";hi".into(),
            cursor_offset: 0
        }
    );
    // Only once: the next backspace deletes normally.
    field.backspace();
    assert_eq!(field.text(), "x ;h|");
}

#[test]
fn backspace_after_another_key_does_not_undo() {
    let mut field = Field::new();
    field.type_keys(";hi!");
    field.backspace();
    assert_eq!(field.text(), "Hoi daar|");
}

#[test]
fn backspace_does_not_undo_after_reset() {
    let mut field = Field::new();
    field.type_keys(";hi");
    field.engine.reset();
    field.backspace();
    assert_eq!(field.text(), "Hoi daa|");
}

#[test]
fn backspace_does_not_undo_a_cursor_hint_expansion() {
    // As in Espanso (undo.rs): a cursor hint disables undo.
    let mut field = Field::new();
    field.type_keys(";dear");
    field.backspace();
    assert_eq!(field.text(), "Dear|,");
}

#[test]
fn undo_of_a_word_trigger_puts_back_the_whole_trigger() {
    // Espanso's undo re-types the matched trigger including its left separator, which
    // stayed in the text, so the separator appears twice (action.rs, Undo). Kept to
    // match Espanso on the Mac.
    let mut field = Field::new();
    field.type_keys("ok brb ");
    field.backspace();
    assert_eq!(field.text(), "ok  brb |");
}

#[test]
fn undo_backspace_can_be_turned_off() {
    let dir = tempdir_with_config("undo_backspace: false\n");
    let mut engine = EspansoEngine::new(&dir).unwrap();
    for c in ";hi".chars() {
        engine.type_text(&c.to_string());
    }
    assert_eq!(engine.backspace(), None);
}

#[test]
fn reset_mid_trigger_stops_it_firing() {
    let mut field = Field::new();
    field.type_keys(";to");
    field.engine.reset();
    field.type_keys("day");
    assert_eq!(field.text(), ";today|");
    assert!(field.expansions.is_empty());
}

#[test]
fn backspace_steps_the_trigger_back() {
    // matcher.rs: Espanso keeps the last states, so a typo can be corrected.
    let mut field = Field::new();
    field.type_keys(";hx");
    field.backspace();
    field.type_keys("i");
    assert_eq!(field.text(), "Hoi daar|");
}

#[test]
fn underscore_files_are_skipped_unless_imported() {
    assert_eq!(Field::new().type_keys(";ignored").text(), ";ignored|");
    assert_eq!(
        Field::new().type_keys(";imported").text(),
        "from an imported file|"
    );
}

#[test]
fn non_ascii_triggers_delete_the_right_number_of_characters() {
    let mut field = Field::new();
    field.type_keys("a;café");
    assert_eq!(field.expansions[0].delete_count, 5);
    assert_eq!(field.text(), "akoffie|");

    // The emoji with skin tone is one character in the text field but two scalars.
    let mut field = Field::new();
    field.type_keys("a;👍🏽");
    assert_eq!(field.expansions[0].delete_count, 2);
    assert_eq!(field.text(), "aprima|");
}

#[test]
fn nested_matches_and_global_variables_render() {
    assert_eq!(
        Field::new().type_keys(";nest").text(),
        "Hoi daar, hoe gaat het?|"
    );
}

#[test]
fn propagate_case_follows_the_typed_trigger() {
    assert_eq!(Field::new().type_keys("alh").text(), "although|");
    assert_eq!(Field::new().type_keys("Alh").text(), "Although|");
    assert_eq!(Field::new().type_keys("ALH").text(), "ALTHOUGH|");
}

#[test]
fn script_variables_fail_until_step_2() {
    let mut field = Field::new();
    field.type_keys(";jitsi");
    assert_eq!(field.text(), ";jitsi|");
    assert!(field.engine.last_error().is_some());
}

#[test]
fn choice_variables_cancel_without_a_picker() {
    let mut field = Field::new();
    field.type_keys(";pick");
    assert_eq!(field.text(), ";pick|");
}

#[test]
fn search_finds_snippets_by_trigger_and_text() {
    let engine = engine();
    let found = engine.search("koffie");
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].triggers, vec![";café".to_string()]);
    assert!(engine
        .search("BRB")
        .iter()
        .any(|s| s.label == "be right back"));
    assert!(engine.search("").len() >= 10);
}

#[test]
fn unsupported_snippets_are_reported() {
    let dir = tempdir_with_matches(
        "matches:\n  - trigger: \";md\"\n    markdown: \"**bold**\"\n  - regex: \"x(?P<n>\\\\d)\"\n    replace: \"{{n}}\"\n",
    );
    let engine = EspansoEngine::new(&dir).unwrap();
    assert_eq!(engine.warnings().len(), 2, "{:?}", engine.warnings());
}

/// A throwaway Espanso folder with the fixture's matches and the given config.
fn tempdir_with_config(config: &str) -> PathBuf {
    let dir = tempdir();
    std::fs::create_dir_all(dir.join("config")).unwrap();
    std::fs::write(dir.join("config/default.yml"), config).unwrap();
    std::fs::create_dir_all(dir.join("match")).unwrap();
    std::fs::copy(fixture().join("match/base.yml"), dir.join("match/base.yml")).unwrap();
    std::fs::copy(
        fixture().join("match/_imported.yml"),
        dir.join("match/_imported.yml"),
    )
    .unwrap();
    dir
}

/// A throwaway Espanso folder with only the given match file.
fn tempdir_with_matches(matches: &str) -> PathBuf {
    let dir = tempdir();
    std::fs::create_dir_all(dir.join("config")).unwrap();
    std::fs::write(dir.join("config/default.yml"), "").unwrap();
    std::fs::create_dir_all(dir.join("match")).unwrap();
    std::fs::write(dir.join("match/base.yml"), matches).unwrap();
    dir
}

fn tempdir() -> PathBuf {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static COUNT: AtomicUsize = AtomicUsize::new(0);
    let dir = std::env::temp_dir().join(format!(
        "espanso-keyboard-test-{}-{}",
        std::process::id(),
        COUNT.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = std::fs::remove_dir_all(&dir);
    dir
}
