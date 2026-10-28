//! Questions a snippet asks while rendering: `choice` and `form` variables (plan step 6).
//!
//! Espanso's renderer asks synchronously, through a `ChoiceSelector` or `FormProvider`,
//! but a keyboard can only ask by showing its own panel and waiting for a tap. So the
//! engine renders with a [`Prompter`] that answers from the answers given so far and,
//! at the first question without one, records it and cancels the render. The engine
//! returns that [`Prompt`]; once answered it renders again from the start, with one
//! more answer, until no question is left.

use std::cell::RefCell;
use std::collections::HashMap;

use espanso_render::extension::choice::{Choice, ChoiceSelector, ChoiceSelectorResult};
use espanso_render::extension::form::{FormProvider, FormProviderResult};
use espanso_render::{Params, Value};

/// A question for the person typing.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum Prompt {
    /// Pick one of `choices` (a `choice` variable).
    Choice { choices: Vec<ChoiceItem> },
    /// Fill in a form: `layout` is Espanso's form text, with `[[name]]` for each field.
    Form {
        layout: String,
        fields: Vec<FormField>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ChoiceItem {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FormField {
    pub name: String,
    pub kind: FieldKind,
    pub default_value: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum FieldKind {
    Text {
        multiline: bool,
    },
    /// One of `values`; Espanso's `choice` and `list` fields both become this.
    Choice {
        values: Vec<String>,
    },
}

/// The answer to a [`Prompt`].
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum Answer {
    Choice { id: String },
    Form { values: HashMap<String, String> },
}

/// Answers questions from the answers given so far; records the first one it can't.
pub struct Prompter<'a> {
    answers: &'a [Answer],
    next: RefCell<usize>,
    /// When set, questions are answered with their defaults (the first choice, the
    /// fields' default values) instead of being asked: for previews.
    use_defaults: bool,
    pub asked: RefCell<Option<Prompt>>,
}

impl<'a> Prompter<'a> {
    pub fn new(answers: &'a [Answer], use_defaults: bool) -> Self {
        Self {
            answers,
            next: RefCell::new(0),
            use_defaults,
            asked: RefCell::new(None),
        }
    }

    /// The next given answer, moving past it.
    fn take(&self) -> Option<&'a Answer> {
        let mut next = self.next.borrow_mut();
        let answer = self.answers.get(*next);
        *next += 1;
        answer
    }
}

impl ChoiceSelector for Prompter<'_> {
    fn show(&self, choices: &[Choice]) -> ChoiceSelectorResult {
        if let Some(Answer::Choice { id }) = self.take() {
            return ChoiceSelectorResult::Success(id.clone());
        }
        if self.use_defaults {
            return match choices.first() {
                Some(choice) => ChoiceSelectorResult::Success(choice.id.to_string()),
                None => ChoiceSelectorResult::Aborted,
            };
        }
        *self.asked.borrow_mut() = Some(Prompt::Choice {
            choices: choices
                .iter()
                .map(|c| ChoiceItem {
                    id: c.id.to_string(),
                    label: c.label.to_string(),
                })
                .collect(),
        });
        ChoiceSelectorResult::Aborted
    }
}

impl FormProvider for Prompter<'_> {
    fn show(&self, layout: &str, fields: &Params, _: &Params) -> FormProviderResult {
        let fields = form_fields(layout, fields);
        if let Some(Answer::Form { values }) = self.take() {
            // Fields left out of the answer get their defaults, as an untouched field would.
            let mut values = values.clone();
            for field in &fields {
                values
                    .entry(field.name.clone())
                    .or_insert_with(|| field.default_value.clone());
            }
            return FormProviderResult::Success(values);
        }
        if self.use_defaults {
            return FormProviderResult::Success(
                fields
                    .into_iter()
                    .map(|f| (f.name, f.default_value))
                    .collect(),
            );
        }
        *self.asked.borrow_mut() = Some(Prompt::Form {
            layout: layout.to_string(),
            fields,
        });
        FormProviderResult::Aborted
    }
}

/// The fields of a form in the order the layout names them. Fields the `fields`
/// parameter doesn't describe are single-line text, as in Espanso.
fn form_fields(layout: &str, params: &Params) -> Vec<FormField> {
    let mut fields: Vec<FormField> = Vec::new();
    let mut rest = layout;
    while let Some(start) = rest.find("[[") {
        let Some(end) = rest[start..].find("]]") else {
            break;
        };
        let name = rest[start + 2..start + end].trim().to_string();
        rest = &rest[start + end + 2..];
        if name.is_empty() || fields.iter().any(|f| f.name == name) {
            continue;
        }
        let spec = match params.get(&name) {
            Some(Value::Object(spec)) => Some(spec),
            _ => None,
        };
        fields.push(form_field(name, spec));
    }
    fields
}

fn form_field(name: String, spec: Option<&Params>) -> FormField {
    let string = |key: &str| match spec.and_then(|s| s.get(key)) {
        Some(Value::String(s)) => Some(s.clone()),
        _ => None,
    };
    let default_value = string("default").unwrap_or_default();
    let kind = match string("type").as_deref() {
        Some("choice" | "list") => FieldKind::Choice {
            values: match spec.and_then(|s| s.get("values")) {
                Some(Value::Array(values)) => values
                    .iter()
                    .filter_map(|v| v.as_string().cloned())
                    .collect(),
                Some(Value::String(lines)) => lines
                    .lines()
                    .map(str::trim)
                    .filter(|l| !l.is_empty())
                    .map(String::from)
                    .collect(),
                _ => Vec::new(),
            },
        },
        _ => FieldKind::Text {
            multiline: matches!(
                spec.and_then(|s| s.get("multiline")),
                Some(Value::Bool(true))
            ),
        },
    };
    FormField {
        name,
        kind,
        default_value,
    }
}
