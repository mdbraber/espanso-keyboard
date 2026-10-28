//! Shared test helpers: the fixture, a simulated text field and a recording script runner.
#![allow(dead_code)]

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use espanso_keyboard_core::{EspansoEngine, Expansion, ScriptOutput, ScriptRunner};
use unicode_segmentation::UnicodeSegmentation;

pub fn fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../fixtures/espanso")
}

/// One call to the script runner.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Call {
    pub script_path: String,
    pub argv: Vec<String>,
    pub env: HashMap<String, String>,
}

type Respond = dyn Fn(&Call) -> anyhow::Result<ScriptOutput> + Send + Sync;

/// A `ScriptRunner` that records its calls and answers with a fixed function.
pub struct TestRunner {
    pub calls: Mutex<Vec<Call>>,
    respond: Box<Respond>,
}

impl TestRunner {
    pub fn new(
        respond: impl Fn(&Call) -> anyhow::Result<ScriptOutput> + Send + Sync + 'static,
    ) -> Arc<Self> {
        Arc::new(Self {
            calls: Mutex::new(Vec::new()),
            respond: Box::new(respond),
        })
    }

    /// Prints `stdout` successfully.
    pub fn printing(stdout: &str) -> Arc<Self> {
        let stdout = stdout.to_string();
        Self::new(move |_| {
            Ok(ScriptOutput {
                stdout: stdout.clone(),
                stderr: String::new(),
                success: true,
            })
        })
    }

    /// Fails as if the script couldn't run.
    pub fn failing() -> Arc<Self> {
        Self::new(|_| anyhow::bail!("no scripts in this test"))
    }

    pub fn calls(&self) -> Vec<Call> {
        self.calls.lock().unwrap().clone()
    }
}

impl ScriptRunner for TestRunner {
    fn run(
        &self,
        script_path: &str,
        argv: &[String],
        env: &HashMap<String, String>,
    ) -> anyhow::Result<ScriptOutput> {
        let call = Call {
            script_path: script_path.to_string(),
            argv: argv.to_vec(),
            env: env.clone(),
        };
        self.calls.lock().unwrap().push(call.clone());
        (self.respond)(&call)
    }
}

pub fn engine() -> EspansoEngine {
    engine_with(TestRunner::failing())
}

pub fn engine_with(runner: Arc<TestRunner>) -> EspansoEngine {
    let engine = EspansoEngine::new(&fixture(), runner).expect("fixture should load");
    assert!(
        engine.warnings().is_empty(),
        "warnings: {:?}",
        engine.warnings()
    );
    engine
}

/// A text field with the cursor at the end of `before`, edited the way the keyboard edits
/// through `textDocumentProxy`: one grapheme cluster per `deleteBackward`.
pub struct Field {
    pub engine: EspansoEngine,
    before: String,
    after: String,
    pub expansions: Vec<Expansion>,
}

impl Field {
    pub fn new() -> Self {
        Self::with(engine())
    }

    pub fn with(engine: EspansoEngine) -> Self {
        Self {
            engine,
            before: String::new(),
            after: String::new(),
            expansions: Vec::new(),
        }
    }

    /// Types `text` one key press (grapheme cluster) at a time.
    pub fn type_keys(&mut self, text: &str) -> &mut Self {
        for key in text.graphemes(true) {
            self.before.push_str(key);
            if let Some(expansion) = self.engine.type_text(key) {
                self.apply(expansion);
            }
        }
        self
    }

    pub fn backspace(&mut self) -> &mut Self {
        match self.engine.backspace() {
            Some(expansion) => self.apply(expansion),
            None => self.delete_backward(1),
        }
        self
    }

    pub fn apply(&mut self, expansion: Expansion) {
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

    pub fn text(&self) -> String {
        format!("{}|{}", self.before, self.after)
    }
}

/// A throwaway Espanso folder with the fixture's matches and the given config.
pub fn tempdir_with_config(config: &str) -> PathBuf {
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
pub fn tempdir_with_matches(matches: &str) -> PathBuf {
    let dir = tempdir();
    std::fs::create_dir_all(dir.join("config")).unwrap();
    std::fs::write(dir.join("config/default.yml"), "").unwrap();
    std::fs::create_dir_all(dir.join("match")).unwrap();
    std::fs::write(dir.join("match/base.yml"), matches).unwrap();
    dir
}

pub fn tempdir() -> PathBuf {
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
