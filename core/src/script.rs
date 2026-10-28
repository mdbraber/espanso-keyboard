/*
 * This file is part of espanso.
 *
 * Copyright (C) 2019-2021 Federico Terzi
 *
 * espanso is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * espanso is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with espanso.  If not, see <https://www.gnu.org/licenses/>.
 */

//! The keyboard's `script` variable: runs `.js` files through a host-supplied
//! [`ScriptRunner`] instead of starting a program. Adapted from Espanso's
//! `espanso-render/src/extension/script.rs`; see docs/script-contract.md.

use std::collections::HashMap;
use std::path::Path;

use espanso_render::{Extension, ExtensionOutput, ExtensionResult, Params, Scope, Value};
use log::{info, warn};
use thiserror::Error;

/// What running a script produced.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ScriptOutput {
    /// Everything printed with `console.log`, joined with newlines.
    pub stdout: String,
    /// Everything printed with `console.error`, plus the message of an uncaught error.
    pub stderr: String,
    /// False when the script threw an uncaught error (a non-zero exit status under Bun).
    pub success: bool,
}

/// Runs a script file; implemented by the host (JavaScriptCore on the iPhone).
pub trait ScriptRunner: Send + Sync {
    /// `argv` is the full argument list, `[runtime, script path, ...rest]`. An `Err` means
    /// the script couldn't run at all (missing file, time limit), which fails the snippet
    /// even with `ignore_error`, as when Espanso can't start the program.
    fn run(
        &self,
        script_path: &str,
        argv: &[String],
        env: &HashMap<String, String>,
    ) -> anyhow::Result<ScriptOutput>;
}

/// Runtimes accepted as the first argument (docs/script-contract.md).
const RUNTIMES: [&str; 3] = ["bun", "node", "deno"];

pub struct ScriptExtension<'a> {
    config_path: String,
    runner: &'a dyn ScriptRunner,
}

impl<'a> ScriptExtension<'a> {
    /// On the iPhone `%CONFIG%` and `%HOME%` both stand for the copied Espanso folder.
    pub fn new(config_path: &Path, runner: &'a dyn ScriptRunner) -> Self {
        Self {
            config_path: config_path.to_string_lossy().into_owned(),
            runner,
        }
    }
}

impl Extension for ScriptExtension<'_> {
    fn name(&self) -> &'static str {
        "script"
    }

    fn calculate(
        &self,
        _: &espanso_render::Context,
        scope: &Scope,
        params: &Params,
    ) -> ExtensionResult {
        let Some(Value::Array(args)) = params.get("args") else {
            return ExtensionResult::Error(ScriptExtensionError::MissingArgsParameter.into());
        };
        let mut args: Vec<String> = args
            .iter()
            .filter_map(|arg| arg.as_string())
            .cloned()
            .collect();

        // From Espanso: replace %HOME% and %CONFIG% in every argument.
        for arg in &mut args {
            if arg.contains("%PACKAGES%") {
                return ExtensionResult::Error(ScriptExtensionError::PackagesUnsupported.into());
            }
            if arg.contains("%HOME%") {
                *arg = arg.replace("%HOME%", &self.config_path);
            }
            if arg.contains("%CONFIG%") {
                *arg = arg.replace("%CONFIG%", &self.config_path);
            }
        }

        // Only `[bun | node | deno, <file>.js, ...]` can run without starting a program.
        match args.as_slice() {
            [runtime, script, ..]
                if RUNTIMES.contains(&runtime.as_str()) && script.ends_with(".js") => {}
            _ => return ExtensionResult::Error(ScriptExtensionError::Unsupported(args).into()),
        }

        let mut env = convert_to_env_variables(scope);
        env.insert("CONFIG".to_string(), self.config_path.clone());

        let output = match self.runner.run(&args[1], &args, &env) {
            Ok(output) => output,
            Err(error) => {
                return ExtensionResult::Error(
                    ScriptExtensionError::ExecutionFailed(args[1].clone(), error).into(),
                )
            }
        };
        let output_str = &output.stdout;
        let error_str = &output.stderr;

        let debug = params
            .get("debug")
            .and_then(|v| v.as_bool())
            .copied()
            .unwrap_or(false);

        if debug {
            info!("debug information for script> {args:?}");
            info!("success: '{}'", output.success);
            info!("stdout: '{output_str}'");
            info!("stderr: '{error_str}'");
            info!("this debug information was shown because the 'debug' option is true.");
        }

        let ignore_error = params
            .get("ignore_error")
            .and_then(|v| v.as_bool())
            .copied()
            .unwrap_or(false);

        if !output.success || !error_str.trim().is_empty() {
            warn!(
                "script exited with success: {} and error: {}",
                output.success, error_str
            );

            if !ignore_error {
                return ExtensionResult::Error(
                    ScriptExtensionError::ExecutionError(error_str.to_string()).into(),
                );
            }
        }

        let trim = params
            .get("trim")
            .and_then(|v| v.as_bool())
            .copied()
            .unwrap_or(true);

        let output = if trim {
            output_str.trim().to_owned()
        } else {
            output_str.to_string()
        };

        ExtensionResult::Success(ExtensionOutput::Single(output))
    }
}

/// From `espanso-render/src/extension/util.rs`, which Espanso doesn't export.
fn convert_to_env_variables(scope: &Scope) -> HashMap<String, String> {
    let mut output = HashMap::new();

    for (key, result) in scope {
        match result {
            ExtensionOutput::Single(value) => {
                let name = format!("ESPANSO_{}", key.to_uppercase());
                output.insert(name, value.clone());
            }
            ExtensionOutput::Multiple(values) => {
                for (sub_key, sub_value) in values {
                    let name = format!("ESPANSO_{}_{}", key.to_uppercase(), sub_key.to_uppercase());
                    output.insert(name, sub_value.clone());
                }
            }
        }
    }

    output
}

#[derive(Error, Debug)]
pub enum ScriptExtensionError {
    #[error("missing 'args' parameter")]
    MissingArgsParameter,

    #[error("only [bun | node | deno, <file>.js, ...] scripts run on the iPhone, not {0:?}")]
    Unsupported(Vec<String>),

    #[error("%PACKAGES% isn't supported on the iPhone")]
    PackagesUnsupported,

    #[error("could not execute script: '`{0}`', error: '`{1:#}`'")]
    ExecutionFailed(String, anyhow::Error),

    #[error("script reported error: '`{0}`'")]
    ExecutionError(String),
}
