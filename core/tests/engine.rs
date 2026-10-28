//! The expansion engine against fixtures/espanso/, through a simulated text field that
//! applies expansions the way the keyboard will (plan step 1).

mod common;

use common::{engine, tempdir_with_config, tempdir_with_matches, Field, TestRunner};
use espanso_keyboard_core::{EspansoEngine, Expansion};

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
            cursor_offset: 0,
            snippet: ";today".into(),
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
            cursor_offset: 1,
            snippet: ";dear".into(),
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
            cursor_offset: 0,
            snippet: String::new(),
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
fn undo_of_a_word_trigger_keeps_the_left_separator_single() {
    // Espanso on the Mac re-types the left separator as well, giving "ok  brb "
    // (action.rs, Undo); the keyboard puts back only what it deleted (docs/decisions.md).
    let mut field = Field::new();
    field.type_keys("ok brb ");
    field.backspace();
    assert_eq!(field.text(), "ok brb |");
    assert_eq!(field.expansions[1].insert, "brb ");

    // At the start of the text there is no left separator.
    let mut field = Field::new();
    field.type_keys("brb.");
    field.backspace();
    assert_eq!(field.text(), "brb.|");
}

#[test]
fn undo_backspace_can_be_turned_off() {
    let dir = tempdir_with_config("undo_backspace: false\n");
    let mut engine = EspansoEngine::new(&dir, TestRunner::failing()).unwrap();
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
fn snippet_does_not_expand_when_its_script_cannot_run() {
    let mut field = Field::new();
    field.type_keys(";jitsi");
    assert_eq!(field.text(), ";jitsi|");
    assert!(field.engine.last_error().is_some());
}

#[test]
fn choice_variables_wait_for_an_answer() {
    // Answering is in tests/features.rs.
    let mut field = Field::new();
    field.type_keys(";pick");
    assert_eq!(field.text(), ";pick|");
    assert!(field.engine.prompt().is_some());
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
    let engine = EspansoEngine::new(&dir, TestRunner::failing()).unwrap();
    // Only the markdown snippet: regex triggers are supported.
    assert_eq!(engine.warnings().len(), 1, "{:?}", engine.warnings());
    assert!(engine.warnings()[0].contains("markdown"));
    // The markdown snippet isn't listed: the keyboard can't type it.
    let listed: Vec<String> = engine
        .search("")
        .into_iter()
        .flat_map(|s| s.triggers)
        .collect();
    assert_eq!(listed, vec!["x(?P<n>\\d)".to_string()]);
}

#[test]
fn regex_trigger_expands_with_its_named_groups() {
    let mut field = Field::new();
    field.type_keys("x ;heyAnna!");
    assert_eq!(field.text(), "x Hey Anna!|");
    assert_eq!(field.expansions[0].delete_count, 9);
}

#[test]
fn regex_trigger_does_not_fire_on_a_partial_match() {
    assert_eq!(Field::new().type_keys(";heyanna!").text(), ";heyanna!|");
}

#[test]
fn backspace_after_a_regex_expansion_restores_the_typed_text() {
    let mut field = Field::new();
    field.type_keys(";heyBo!");
    field.backspace();
    assert_eq!(field.text(), ";heyBo!|");
}

#[test]
fn reset_clears_the_regex_buffer() {
    let mut field = Field::new();
    field.type_keys(";hey");
    field.engine.reset();
    field.type_keys("Bo!");
    assert_eq!(field.text(), ";heyBo!|");
}

#[test]
fn backspace_steps_the_regex_buffer_back() {
    let mut field = Field::new();
    field.type_keys(";heyBx");
    field.backspace();
    field.type_keys("o!");
    assert_eq!(field.text(), "Hey Bo!|");
}

#[test]
fn invalid_regexes_are_reported() {
    let dir = tempdir_with_matches("matches:\n  - regex: \"(unclosed\"\n    replace: x\n");
    let engine = EspansoEngine::new(&dir, TestRunner::failing()).unwrap();
    assert_eq!(engine.warnings().len(), 1, "{:?}", engine.warnings());
    assert!(engine.warnings()[0].contains("invalid regex"));
}
