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

//! Code copied from Espanso at the commit pinned in `Cargo.toml` and adapted for the
//! keyboard. Each function names the upstream file it came from; compare them when
//! updating Espanso (docs/plan.md, "Updating Espanso").

use espanso_config::matches::{Match, MatchCause, MatchEffect, UpperCasingStyle};
use espanso_match::rolling::{RollingMatch, StringMatchOptions};
use espanso_render::{CasingStyle, Template, Variable};
use unicode_segmentation::UnicodeSegmentation;

/// From `espanso/src/cli/worker/engine/process/middleware/matcher/convert.rs`
/// (`MatchConverter::get_rolling_matches`), without the built-in matches, which belong
/// to the desktop app.
pub fn rolling_matches(matches: &[&Match]) -> Vec<RollingMatch<i32>> {
    let mut rolling = Vec::new();
    for m in matches {
        if let MatchCause::Trigger(cause) = &m.cause {
            for trigger in &cause.triggers {
                rolling.push(RollingMatch::from_string(
                    m.id,
                    trigger,
                    &StringMatchOptions {
                        case_insensitive: cause.propagate_case,
                        left_word: cause.left_word,
                        right_word: cause.right_word,
                    },
                ));
            }
        }
    }
    rolling
}

/// From `espanso/src/cli/worker/engine/process/middleware/render/mod.rs`.
pub fn convert_to_template(m: &Match) -> Option<Template> {
    if let MatchEffect::Text(text_effect) = &m.effect {
        let ids = if let MatchCause::Trigger(cause) = &m.cause {
            cause.triggers.clone()
        } else {
            Vec::new()
        };

        Some(Template {
            ids,
            body: text_effect.replace.clone(),
            vars: convert_vars(text_effect.vars.clone()),
        })
    } else {
        None
    }
}

/// From `espanso/src/cli/worker/engine/process/middleware/render/mod.rs`.
fn convert_vars(vars: Vec<espanso_config::matches::Variable>) -> Vec<Variable> {
    vars.into_iter().map(convert_var).collect()
}

/// From `espanso/src/cli/worker/engine/process/middleware/render/mod.rs`.
pub fn convert_var(var: espanso_config::matches::Variable) -> Variable {
    Variable {
        name: var.name,
        var_type: var.var_type,
        params: convert_params(var.params),
        inject_vars: var.inject_vars,
        depends_on: var.depends_on,
    }
}

/// From `espanso/src/cli/worker/engine/process/middleware/render/mod.rs`.
fn convert_params(params: espanso_config::matches::Params) -> espanso_render::Params {
    let mut new_params = espanso_render::Params::new();
    for (key, value) in params {
        new_params.insert(key, convert_value(value));
    }
    new_params
}

/// From `espanso/src/cli/worker/engine/process/middleware/render/mod.rs`.
fn convert_value(value: espanso_config::matches::Value) -> espanso_render::Value {
    match value {
        espanso_config::matches::Value::Null => espanso_render::Value::Null,
        espanso_config::matches::Value::Bool(v) => espanso_render::Value::Bool(v),
        espanso_config::matches::Value::Number(n) => match n {
            espanso_config::matches::Number::Integer(i) => {
                espanso_render::Value::Number(espanso_render::Number::Integer(i))
            }
            espanso_config::matches::Number::Float(f) => {
                espanso_render::Value::Number(espanso_render::Number::Float(f.into_inner()))
            }
        },
        espanso_config::matches::Value::String(s) => espanso_render::Value::String(s),
        espanso_config::matches::Value::Array(v) => {
            espanso_render::Value::Array(v.into_iter().map(convert_value).collect())
        }
        espanso_config::matches::Value::Object(params) => {
            espanso_render::Value::Object(convert_params(params))
        }
    }
}

/// From `espanso/src/cli/worker/engine/process/middleware/render/mod.rs`
/// (`RendererAdapter::render`), as one function of the match and the typed trigger.
pub fn casing_style(m: &Match, trigger: &str) -> CasingStyle {
    match &m.cause {
        MatchCause::Trigger(cause) if cause.propagate_case => {
            calculate_casing_style(trigger, Some(cause.uppercase_style.clone()))
        }
        _ => CasingStyle::None,
    }
}

/// From `espanso/src/cli/worker/engine/process/middleware/render/mod.rs`.
fn calculate_casing_style(
    trigger: &str,
    uppercasing_style: Option<UpperCasingStyle>,
) -> CasingStyle {
    let mut first_alphabetic = None;
    let mut second_alphabetic = None;

    for c in trigger.chars() {
        if c.is_alphabetic() {
            if first_alphabetic.is_none() {
                first_alphabetic = Some(c);
            } else if second_alphabetic.is_none() {
                second_alphabetic = Some(c);
            } else {
                break;
            }
        }
    }

    if let Some(first) = first_alphabetic {
        if let Some(second) = second_alphabetic {
            if first.is_uppercase() {
                if second.is_uppercase() {
                    CasingStyle::Uppercase
                } else {
                    match uppercasing_style {
                        Some(UpperCasingStyle::CapitalizeWords) => CasingStyle::CapitalizeWords,
                        _ => CasingStyle::Capitalize,
                    }
                }
            } else {
                CasingStyle::None
            }
        } else if first.is_uppercase() {
            match uppercasing_style {
                Some(UpperCasingStyle::Capitalize) => CasingStyle::Capitalize,
                Some(UpperCasingStyle::CapitalizeWords) => CasingStyle::CapitalizeWords,
                _ => CasingStyle::Uppercase,
            }
        } else {
            CasingStyle::None
        }
    } else {
        CasingStyle::None
    }
}

/// From `espanso-engine/src/process/middleware/cursor_hint.rs`: removes `$|$` and
/// returns how many characters (grapheme clusters) the cursor must move left.
pub fn process_cursor_hint(body: String) -> (String, Option<usize>) {
    if let Some(index) = body.find("$|$") {
        // Convert the byte index to a char index
        let char_str = &body[0..index];
        let char_index = char_str.graphemes(true).count();
        let total_size = body.graphemes(true).count();

        // Remove the $|$ placeholder
        let body = body.replace("$|$", "");

        // Calculate the amount of rewind moves needed (LEFT ARROW).
        // Subtract also 3, equal to the number of chars of the placeholder "$|$"
        let moves = total_size - char_index - 3;
        (body, Some(moves))
    } else {
        (body, None)
    }
}
