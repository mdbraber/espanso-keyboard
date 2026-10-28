//! Adding and editing snippets in match files as text (plan step 6, item 6).

use espanso_keyboard_core::edit::{append_snippet, replace_snippet, snippet_block};

const FILE: &str = r#"# My snippets
global_vars:
  - name: me
    type: echo
    params:
      echo: Marius

matches:
  # Greetings
  - trigger: ";hi"
    replace: "Hoi {{me}}"

  - triggers: [";bye", ";doei"]
    replace: Doei!
    word: true

  # Dates
  - replace: "{{today}}"
    trigger: ';today'
    vars:
      - name: today
        type: date
        params:
          format: "%Y-%m-%d"

  - regex: ";hey(?P<name>\\w+)!"
    replace: "Hey {{name}}!"
"#;

fn block(key: &str) -> Option<String> {
    snippet_block(FILE.into(), key.into())
}

#[test]
fn finds_a_snippet_by_its_trigger_in_any_quoting() {
    assert_eq!(
        block(";hi").unwrap(),
        "  - trigger: \";hi\"\n    replace: \"Hoi {{me}}\""
    );
    assert!(block(";today")
        .unwrap()
        .starts_with("  - replace: \"{{today}}\"\n    trigger: ';today'"));
    assert!(
        block(";today").unwrap().ends_with("format: \"%Y-%m-%d\""),
        "a snippet ends before the next one's comment"
    );
}

#[test]
fn finds_a_snippet_by_its_first_trigger_or_regex() {
    assert!(block(";bye").unwrap().contains("word: true"));
    assert_eq!(
        block(";doei"),
        None,
        "only the first trigger names a snippet"
    );
    assert!(block(";hey(?P<name>\\w+)!")
        .unwrap()
        .contains("Hey {{name}}!"));
    assert_eq!(block(";nope"), None);
    assert_eq!(block("me"), None, "global variables aren't snippets");
}

#[test]
fn replacing_a_snippet_changes_only_its_lines() {
    let new = "  - trigger: \";hi\"\n    replace: \"Hallo {{me}}\"\n    label: Groet";
    let edited = replace_snippet(FILE.into(), ";hi".into(), new.into()).unwrap();
    assert_eq!(
        edited,
        FILE.replace(
            "    replace: \"Hoi {{me}}\"",
            "    replace: \"Hallo {{me}}\"\n    label: Groet"
        )
    );
    assert_eq!(
        replace_snippet(FILE.into(), ";nope".into(), new.into()),
        None
    );
}

#[test]
fn appending_adds_an_item_at_the_end_of_the_list() {
    let edited = append_snippet(
        FILE.into(),
        ";new".into(),
        "Line \"one\"\nline two".into(),
        Some("Nieuw".into()),
        true,
    );
    assert!(edited.starts_with(FILE.trim_end()));
    assert!(edited.ends_with(
        "\n  - trigger: \";new\"\n    replace: \"Line \\\"one\\\"\\nline two\"\n    label: \"Nieuw\"\n    word: true\n"
    ));
}

#[test]
fn appending_goes_before_a_top_level_key_after_the_list() {
    let file = "matches:\n    - trigger: a\n      replace: b\n\n# Later\nglobal_vars: []\n";
    let edited = append_snippet(file.into(), "c".into(), "d".into(), None, false);
    assert_eq!(
        edited,
        "matches:\n    - trigger: a\n      replace: b\n    - trigger: \"c\"\n      replace: \"d\"\n\n# Later\nglobal_vars: []\n",
        "the new item keeps the list's indentation"
    );
}

#[test]
fn appending_to_a_new_or_empty_file_starts_a_list() {
    assert_eq!(
        append_snippet(String::new(), ";x".into(), "y".into(), None, false),
        "matches:\n  - trigger: \";x\"\n    replace: \"y\"\n"
    );
    assert_eq!(
        append_snippet("matches: []\n".into(), ";x".into(), "y".into(), None, false),
        "matches:\n  - trigger: \";x\"\n    replace: \"y\"\n"
    );
}

#[test]
fn appended_snippets_load_in_espanso() {
    let dir = std::env::temp_dir().join(format!("espanso-keyboard-edit-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("config")).unwrap();
    std::fs::create_dir_all(dir.join("match")).unwrap();
    std::fs::write(dir.join("config/default.yml"), "").unwrap();
    let file = append_snippet(
        String::new(),
        ";q".into(),
        "a \"quote\" and a \\ backslash".into(),
        None,
        false,
    );
    std::fs::write(dir.join("match/iphone.yml"), file).unwrap();

    struct NoScripts;
    impl espanso_keyboard_core::ScriptRunner for NoScripts {
        fn run(
            &self,
            _: &str,
            _: &[String],
            _: &std::collections::HashMap<String, String>,
        ) -> anyhow::Result<espanso_keyboard_core::ScriptOutput> {
            anyhow::bail!("no scripts")
        }
    }
    let mut engine =
        espanso_keyboard_core::EspansoEngine::new(&dir, std::sync::Arc::new(NoScripts)).unwrap();
    assert!(engine.warnings().is_empty(), "{:?}", engine.warnings());
    let mut expansion = None;
    for c in ";q".chars() {
        expansion = engine.type_text(&c.to_string()).or(expansion);
    }
    assert_eq!(expansion.unwrap().insert, "a \"quote\" and a \\ backslash");
}

#[test]
fn lists_without_indentation_work_too() {
    let file = "matches:\n- trigger: a\n  replace: b\n- trigger: c\n  replace: d\n";
    assert_eq!(
        snippet_block(file.into(), "c".into()).unwrap(),
        "- trigger: c\n  replace: d"
    );
    assert_eq!(
        append_snippet(file.into(), "e".into(), "f".into(), None, false),
        format!("{file}- trigger: \"e\"\n  replace: \"f\"\n")
    );
}
