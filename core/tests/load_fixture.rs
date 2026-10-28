use std::path::PathBuf;

use espanso_keyboard_core::load_summary;

fn fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../fixtures/espanso")
}

#[test]
fn loads_the_fixture_folder_with_espanso_config() {
    let summary = load_summary(&fixture()).expect("fixture should load");

    assert!(summary.warnings.is_empty(), "warnings: {:?}", summary.warnings);
    assert!(summary.triggers.contains(&";jitsi".to_string()), "triggers: {:?}", summary.triggers);
    assert!(summary.triggers.contains(&";today".to_string()), "triggers: {:?}", summary.triggers);
}

#[test]
fn skips_match_files_starting_with_an_underscore() {
    let summary = load_summary(&fixture()).expect("fixture should load");

    assert!(!summary.triggers.contains(&";ignored".to_string()), "triggers: {:?}", summary.triggers);
}
