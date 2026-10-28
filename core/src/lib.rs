//! Espanso snippet expansion for an iPhone keyboard extension.
//!
//! [`EspansoEngine`] turns typed characters into expansions with Espanso's own config,
//! match and render libraries. `script` variables run through a host-supplied
//! [`ScriptRunner`]. The Swift interface follows in docs/plan.md.

mod engine;
mod espanso;
mod script;

use std::path::Path;

pub use engine::{EspansoEngine, Expansion, SnippetSummary};
pub use script::{ScriptOutput, ScriptRunner};

use anyhow::Result;

/// What loading an Espanso folder produced.
#[derive(Debug)]
pub struct LoadSummary {
    /// Number of matches active under the default configuration.
    pub match_count: usize,
    /// Every trigger of those matches, in load order.
    pub triggers: Vec<String>,
    /// Non-fatal problems Espanso reported while loading, one per line.
    pub warnings: Vec<String>,
}

/// Loads an Espanso configuration folder (the one containing `config/` and `match/`).
pub fn load_summary(base_path: &Path) -> Result<LoadSummary> {
    let (config_store, match_store, non_fatal_errors) = espanso_config::load(base_path)?;
    let paths = config_store.default().match_paths().to_vec();
    let set = match_store.query(&paths);

    let triggers = set
        .matches
        .iter()
        .flat_map(|m| match &m.cause {
            espanso_config::matches::MatchCause::Trigger(cause) => cause.triggers.clone(),
            _ => Vec::new(),
        })
        .collect();

    Ok(LoadSummary {
        match_count: set.matches.len(),
        triggers,
        warnings: non_fatal_errors.iter().map(|e| format!("{e:?}")).collect(),
    })
}
