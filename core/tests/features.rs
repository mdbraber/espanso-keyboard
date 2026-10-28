//! Plan step 6 in the engine: questions (`choice`, `form`), `clipboard`, inserting a
//! snippet by id, previews, completions and match files.

mod common;

use std::collections::HashMap;
use std::sync::Arc;

use common::{engine, Field};
use espanso_keyboard_core::{
    Answer, ChoiceItem, ClipboardReader, EspansoEngine, FieldKind, Prompt,
};

fn id(engine: &EspansoEngine, trigger: &str) -> i32 {
    engine
        .search("")
        .into_iter()
        .find(|s| s.triggers.iter().any(|t| t == trigger))
        .unwrap_or_else(|| panic!("no {trigger}"))
        .id
}

fn choice(id: &str) -> Answer {
    Answer::Choice { id: id.into() }
}

#[test]
fn a_choice_asks_and_expands_with_the_answer() {
    let mut field = Field::new();
    field.type_keys(";pick");
    assert_eq!(field.text(), ";pick|");
    assert_eq!(
        field.engine.prompt(),
        Some(&Prompt::Choice {
            choices: vec![
                ChoiceItem {
                    id: "appel".into(),
                    label: "appel".into()
                },
                ChoiceItem {
                    id: "peer".into(),
                    label: "peer".into()
                },
            ]
        })
    );
    let expansion = field.engine.answer(choice("peer")).expect("expands");
    assert_eq!(expansion.delete_count, 5);
    assert_eq!(expansion.insert, "peer");
    assert_eq!(field.engine.prompt(), None);
}

#[test]
fn questions_follow_one_another() {
    let mut field = Field::new();
    field.type_keys(";two");
    assert!(matches!(field.engine.prompt(), Some(Prompt::Choice { .. })));
    assert_eq!(field.engine.answer(choice("groot")), None);
    let Some(Prompt::Choice { choices }) = field.engine.prompt() else {
        panic!("a second question")
    };
    assert_eq!(choices[1].label, "Peer");
    let expansion = field.engine.answer(choice("peer")).expect("expands");
    assert_eq!(expansion.insert, "groot peer");
}

#[test]
fn a_form_asks_for_its_fields() {
    let mut field = Field::new();
    field.type_keys(";form");
    let Some(Prompt::Form { layout, fields }) = field.engine.prompt().cloned() else {
        panic!("a form")
    };
    assert_eq!(layout, "Hoi [[name]], tot [[when]]!");
    assert_eq!(fields[0].name, "name");
    assert_eq!(fields[0].kind, FieldKind::Text { multiline: false });
    assert_eq!(fields[1].name, "when");
    assert_eq!(
        fields[1].kind,
        FieldKind::Choice {
            values: vec!["morgen".into(), "vandaag".into()]
        }
    );
    assert_eq!(fields[1].default_value, "morgen");

    let values = HashMap::from([("name".to_string(), "Anna".to_string())]);
    let expansion = field
        .engine
        .answer(Answer::Form { values })
        .expect("expands");
    assert_eq!(
        expansion.insert, "Hoi Anna, tot morgen!",
        "an unanswered field keeps its default"
    );
}

#[test]
fn typing_drops_an_unanswered_question() {
    let mut field = Field::new();
    field.type_keys(";pick");
    field.type_keys("x");
    assert_eq!(field.engine.prompt(), None);
    assert_eq!(field.engine.answer(choice("peer")), None);
}

struct Clipboard(&'static str);

impl ClipboardReader for Clipboard {
    fn text(&self) -> Option<String> {
        Some(self.0.to_string())
    }
}

#[test]
fn clipboard_variables_read_the_host_clipboard() {
    let mut field = Field::new();
    field.engine.set_clipboard(Arc::new(Clipboard("hallo")));
    field.type_keys(";clip");
    assert_eq!(field.text(), "Gekopieerd: hallo|");
}

#[test]
fn clipboard_variables_fail_without_a_clipboard() {
    let mut field = Field::new();
    field.type_keys(";clip");
    assert_eq!(field.text(), ";clip|");
    assert!(field.engine.last_error().is_some());
}

#[test]
fn a_snippet_inserts_by_id_replacing_what_was_typed() {
    let mut engine = engine();
    let hi = id(&engine, ";hi");
    let expansion = engine.insert_snippet(hi, 2).expect("expands");
    assert_eq!(
        (expansion.delete_count, expansion.insert.as_str()),
        (2, "Hoi daar")
    );
    assert_eq!(expansion.snippet, ";hi");
}

#[test]
fn a_preview_renders_with_defaults_and_without_the_cursor_marker() {
    let engine = engine();
    assert_eq!(engine.preview(id(&engine, ";pick")).unwrap(), "appel");
    assert_eq!(engine.preview(id(&engine, ";dear")).unwrap(), "Dear ,");
    assert_eq!(
        engine.preview(id(&engine, ";form")).unwrap(),
        "Hoi , tot morgen!"
    );
}

#[test]
fn completions_follow_the_typed_start_of_a_trigger() {
    let engine = engine();
    let triggers = |before: &str| -> Vec<(String, u32)> {
        engine
            .complete(before)
            .into_iter()
            .map(|c| (c.trigger, c.typed))
            .collect()
    };
    assert_eq!(triggers("x ;jit"), vec![(";jitsi".into(), 4)]);
    assert_eq!(triggers("x ;to"), vec![(";today".into(), 3)]);
    // ";t" begins both ";today" and ";two"; equally long starts are sorted by trigger.
    assert_eq!(
        triggers(";t"),
        vec![(";today".into(), 2), (";two".into(), 2)]
    );
    assert!(triggers(";").is_empty(), "one character is too little");
    assert!(
        triggers("ok ;jitsi").is_empty(),
        "a whole trigger isn't a completion"
    );
    // "alh" starts with a letter: three characters would be the whole trigger.
    assert!(triggers("ok al").is_empty());
    assert!(triggers("plain text").is_empty());
}

#[test]
fn snippets_know_their_match_file() {
    let engine = engine();
    let files: HashMap<String, String> = engine
        .search("")
        .into_iter()
        .map(|s| (s.triggers[0].clone(), s.file))
        .collect();
    assert_eq!(files[";today"], "base.yml");
    assert_eq!(
        files[";imported"], "base.yml",
        "imported matches count as the importing file's"
    );
}

#[test]
fn snippet_details_include_the_raw_text_and_variables() {
    let engine = engine();
    let jitsi = engine.search(";jitsi").into_iter().next().unwrap();
    assert_eq!(jitsi.replace, "https://meet.jit.si/mdb-{{room}}");
    assert_eq!(jitsi.vars, vec!["room".to_string()]);
    assert!(!jitsi.is_regex);
}

#[test]
fn a_regex_snippet_is_counted_by_its_regex() {
    let mut field = Field::new();
    field.type_keys(";heyBo!");
    assert_eq!(field.expansions[0].snippet, ";hey(?P<name>[A-Z][a-z]+)!");
}

#[test]
fn a_regex_snippet_previews_from_an_example_of_its_trigger() {
    let engine = engine();
    let hey = engine
        .search("Hey {{name}}")
        .into_iter()
        .find(|s| s.is_regex)
        .unwrap()
        .id;
    assert!(
        engine.preview(hey).is_err(),
        "without an example its group is missing"
    );
    assert_eq!(engine.preview_typed(hey, ";heyAnna!").unwrap(), "Hey Anna!");
    let wrong = engine.preview_typed(hey, ";hello").unwrap_err().to_string();
    assert!(wrong.contains("doesn't match"), "{wrong}");
}
