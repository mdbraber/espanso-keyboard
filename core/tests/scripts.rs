//! `script` variables through a test `ScriptRunner` (plan step 2).

mod common;

use std::path::Path;

use common::{engine_with, fixture, tempdir_with_matches, Field, TestRunner};
use espanso_keyboard_core::{EspansoEngine, ScriptOutput};

/// A field on a throwaway Espanso folder holding one `;s` snippet with the given variable.
fn field_with_var(var: &str, runner: std::sync::Arc<TestRunner>) -> (Field, std::path::PathBuf) {
    let matches = format!(
        "matches:\n  - trigger: \";s\"\n    replace: \"[{{{{out}}}}]\"\n    vars:\n      - name: out\n{var}"
    );
    let dir = tempdir_with_matches(&matches);
    let engine = EspansoEngine::new(&dir, runner).expect("folder should load");
    assert!(engine.warnings().is_empty(), "{:?}", engine.warnings());
    (Field::with(engine), dir)
}

fn script_var(args: &str, extra: &str) -> String {
    format!("        type: script\n        params:\n          args: {args}\n{extra}")
}

fn output(stdout: &str, stderr: &str, success: bool) -> ScriptOutput {
    ScriptOutput {
        stdout: stdout.into(),
        stderr: stderr.into(),
        success,
    }
}

fn path(base: &Path, rest: &str) -> String {
    format!("{}/{rest}", base.display())
}

#[test]
fn jitsi_calls_the_runner_with_bun_argv() {
    let runner = TestRunner::printing("abcdefghjk\n");
    let mut field = Field::with(engine_with(runner.clone()));
    field.type_keys(";jitsi");

    assert_eq!(field.text(), "https://meet.jit.si/mdb-abcdefghjk|");
    let calls = runner.calls();
    assert_eq!(calls.len(), 1);
    let script = path(&fixture(), "scripts/jitsi.js");
    assert_eq!(
        calls[0].argv,
        vec!["bun".to_string(), script.clone(), "10".to_string()]
    );
    assert_eq!(calls[0].script_path, script);
    assert_eq!(
        calls[0].env.get("CONFIG"),
        Some(&fixture().display().to_string())
    );
}

#[test]
fn earlier_variables_appear_in_env() {
    let runner = TestRunner::printing("Hallo Anna!");
    let mut field = Field::with(engine_with(runner.clone()));
    field.type_keys(";hallo");

    assert_eq!(field.text(), "Hallo Anna!|");
    assert_eq!(
        runner.calls()[0].env.get("ESPANSO_WHO"),
        Some(&"Anna".to_string())
    );
}

#[test]
fn error_output_fails_the_snippet() {
    let runner = TestRunner::new(|_| Ok(output("ok", "boom\n", true)));
    let (mut field, _) = field_with_var(&script_var("[bun, \"%CONFIG%/x.js\"]", ""), runner);
    field.type_keys(";s");
    assert_eq!(field.text(), ";s|");
    assert!(field.engine.last_error().unwrap().contains("boom"));
}

#[test]
fn a_thrown_error_fails_the_snippet() {
    let runner = TestRunner::new(|_| Ok(output("partial", "", false)));
    let (mut field, _) = field_with_var(&script_var("[bun, \"%CONFIG%/x.js\"]", ""), runner);
    field.type_keys(";s");
    assert_eq!(field.text(), ";s|");
}

#[test]
fn ignore_error_keeps_the_output() {
    let runner = TestRunner::new(|_| Ok(output("ok\n", "boom", false)));
    let (mut field, _) = field_with_var(
        &script_var("[bun, \"%CONFIG%/x.js\"]", "          ignore_error: true\n"),
        runner,
    );
    field.type_keys(";s");
    assert_eq!(field.text(), "[ok]|");
}

#[test]
fn ignore_error_does_not_cover_a_script_that_cannot_run() {
    let (mut field, _) = field_with_var(
        &script_var("[bun, \"%CONFIG%/x.js\"]", "          ignore_error: true\n"),
        TestRunner::failing(),
    );
    field.type_keys(";s");
    assert_eq!(field.text(), ";s|");
}

#[test]
fn output_is_trimmed_unless_trim_is_false() {
    let (mut field, _) = field_with_var(
        &script_var("[bun, \"%CONFIG%/x.js\"]", ""),
        TestRunner::printing("  hi \n"),
    );
    field.type_keys(";s");
    assert_eq!(field.text(), "[hi]|");

    let (mut field, _) = field_with_var(
        &script_var("[bun, \"%CONFIG%/x.js\"]", "          trim: false\n"),
        TestRunner::printing("  hi \n"),
    );
    field.type_keys(";s");
    assert_eq!(field.text(), "[  hi \n]|");
}

#[test]
fn config_and_home_point_to_the_espanso_folder() {
    let runner = TestRunner::printing("x");
    let (mut field, dir) = field_with_var(
        &script_var("[node, \"%HOME%/a.js\", \"%CONFIG%/b\"]", ""),
        runner.clone(),
    );
    field.type_keys(";s");
    assert_eq!(
        runner.calls()[0].argv,
        vec!["node".to_string(), path(&dir, "a.js"), path(&dir, "b")]
    );
}

#[test]
fn only_javascript_files_run() {
    for args in [
        "[bash, \"%CONFIG%/x.sh\"]",
        "[bun, \"%CONFIG%/x.ts\"]",
        "[python3, \"%CONFIG%/x.js\"]",
        "[bun]",
        "[bun, \"%PACKAGES%/x.js\"]",
    ] {
        let runner = TestRunner::printing("x");
        let (mut field, _) = field_with_var(&script_var(args, ""), runner.clone());
        field.type_keys(";s");
        assert_eq!(field.text(), ";s|", "{args}");
        assert!(runner.calls().is_empty(), "{args}");
        assert!(field.engine.last_error().is_some(), "{args}");
    }
    for runtime in ["bun", "node", "deno"] {
        let (mut field, _) = field_with_var(
            &script_var(&format!("[{runtime}, x.js]"), ""),
            TestRunner::printing("x"),
        );
        field.type_keys(";s");
        assert_eq!(field.text(), "[x]|", "{runtime}");
    }
}

#[test]
fn shell_variables_fail_cleanly() {
    let runner = TestRunner::printing("x");
    let (mut field, _) = field_with_var(
        "        type: shell\n        params:\n          cmd: \"echo hi\"\n",
        runner.clone(),
    );
    field.type_keys(";s");
    assert_eq!(field.text(), ";s|");
    assert!(runner.calls().is_empty());
}

#[test]
fn regex_groups_reach_the_script_as_variables() {
    let runner = TestRunner::printing("Hallo Bo!");
    let mut field = Field::with(engine_with(runner.clone()));
    field.type_keys(";greetBo.");
    assert_eq!(field.text(), "Hallo Bo!|");
    assert_eq!(
        runner.calls()[0].env.get("ESPANSO_WHO"),
        Some(&"Bo".to_string())
    );
}
