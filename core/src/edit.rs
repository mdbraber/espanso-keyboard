//! Adding and editing snippets in Espanso match files from the iPhone (docs/decisions.md,
//! "Snippets can be added and edited on the iPhone").
//!
//! These work on the file's text: only the lines of the one snippet change, so the rest
//! of the file, comments and layout included, stays exactly as it was. A snippet is one
//! item of the top-level `matches:` list, found by its trigger (or regex).

use std::ops::Range;

/// The text of the snippet whose first trigger (or regex) is `key`, as it is in the file:
/// its lines from the `-` that starts it, with their indentation.
#[uniffi::export]
pub fn snippet_block(file: String, key: String) -> Option<String> {
    let lines: Vec<&str> = file.split('\n').collect();
    let range = locate(&lines, &key)?;
    Some(lines[range].join("\n"))
}

/// The file with the snippet whose first trigger (or regex) is `key` replaced by `block`
/// (a whole list item, as [`snippet_block`] returns it), or `None` if it isn't there.
#[uniffi::export]
pub fn replace_snippet(file: String, key: String, block: String) -> Option<String> {
    let lines: Vec<&str> = file.split('\n').collect();
    let range = locate(&lines, &key)?;
    let block = block.trim_end_matches('\n');
    let mut out: Vec<&str> = lines[..range.start].to_vec();
    out.extend(block.split('\n'));
    out.extend(&lines[range.end..]);
    Some(out.join("\n"))
}

/// The file with a new snippet at the end of its `matches:` list; a file without one
/// (or a new, empty file) gets a `matches:` list.
#[uniffi::export]
pub fn append_snippet(
    file: String,
    trigger: String,
    replace: String,
    label: Option<String>,
    word: bool,
) -> String {
    let lines: Vec<&str> = file.split('\n').collect();
    let Some(matches) = matches_line(&lines) else {
        let mut out = file.trim_end_matches('\n').to_string();
        if !out.is_empty() {
            out.push_str("\n\n");
        }
        out.push_str("matches:\n");
        out.push_str(&item(2, &trigger, &replace, label.as_deref(), word));
        return out;
    };
    let indent = item_indent(&lines, matches).unwrap_or(2);
    let block = item(indent, &trigger, &replace, label.as_deref(), word);

    // Insert after the list's last item: before the next top-level key, or at the end,
    // leaving blank lines and comments that follow the list where they are.
    let end = list_end(&lines, matches, indent);
    let mut insert_at = end;
    while insert_at > matches + 1 && is_blank_or_comment(lines[insert_at - 1]) {
        insert_at -= 1;
    }
    let mut out: Vec<String> = lines[..insert_at].iter().map(|l| l.to_string()).collect();
    if out
        .get(matches)
        .is_some_and(|l| l.trim_end() == "matches: []")
    {
        out[matches] = "matches:".to_string();
    }
    out.extend(block.trim_end_matches('\n').split('\n').map(String::from));
    out.extend(lines[insert_at..].iter().map(|l| l.to_string()));
    let mut text = out.join("\n");
    if !text.ends_with('\n') {
        text.push('\n');
    }
    text
}

/// One `matches:` item, written as Espanso's documentation writes snippets.
fn item(indent: usize, trigger: &str, replace: &str, label: Option<&str>, word: bool) -> String {
    let pad = " ".repeat(indent);
    let mut text = format!(
        "{pad}- trigger: {}\n{pad}  replace: {}\n",
        quote(trigger),
        quote(replace)
    );
    if let Some(label) = label.filter(|l| !l.is_empty()) {
        text.push_str(&format!("{pad}  label: {}\n", quote(label)));
    }
    if word {
        text.push_str(&format!("{pad}  word: true\n"));
    }
    text
}

/// A YAML double-quoted string.
fn quote(text: &str) -> String {
    let mut quoted = String::from("\"");
    for c in text.chars() {
        match c {
            '"' => quoted.push_str("\\\""),
            '\\' => quoted.push_str("\\\\"),
            '\n' => quoted.push_str("\\n"),
            '\t' => quoted.push_str("\\t"),
            '\r' => quoted.push_str("\\r"),
            c if c.is_control() => quoted.push_str(&format!("\\u{:04X}", c as u32)),
            c => quoted.push(c),
        }
    }
    quoted.push('"');
    quoted
}

fn is_blank_or_comment(line: &str) -> bool {
    let trimmed = line.trim_start();
    trimmed.is_empty() || trimmed.starts_with('#')
}

fn indent_of(line: &str) -> usize {
    line.len() - line.trim_start_matches(' ').len()
}

/// The line of the top-level `matches:` key.
fn matches_line(lines: &[&str]) -> Option<usize> {
    lines.iter().position(|l| l.starts_with("matches:"))
}

/// The indentation of the `-` of the list's items, from its first item.
fn item_indent(lines: &[&str], matches: usize) -> Option<usize> {
    let first = lines[matches + 1..]
        .iter()
        .find(|l| !is_blank_or_comment(l))?;
    first
        .trim_start()
        .starts_with('-')
        .then(|| indent_of(first))
}

/// The line after the `matches:` list: the next top-level key, or the end of the file.
fn list_end(lines: &[&str], matches: usize, indent: usize) -> usize {
    (matches + 1..lines.len())
        .find(|&i| {
            let line = lines[i];
            !is_blank_or_comment(line)
                && indent_of(line) < indent.max(1)
                && !line.trim_start().starts_with('-')
        })
        .unwrap_or(lines.len())
}

/// The lines of the item whose first trigger (or regex) is `key`. An item runs from its
/// `-` to the next item or the end of the list, without the blank lines and comments
/// before the next one.
fn locate(lines: &[&str], key: &str) -> Option<Range<usize>> {
    let matches = matches_line(lines)?;
    let indent = item_indent(lines, matches)?;
    let end = list_end(lines, matches, indent);
    let is_item = |line: &str| indent_of(line) == indent && line.trim_start().starts_with('-');

    let starts: Vec<usize> = (matches + 1..end).filter(|&i| is_item(lines[i])).collect();
    for (n, &start) in starts.iter().enumerate() {
        let mut stop = starts.get(n + 1).copied().unwrap_or(end);
        while stop > start + 1 && is_blank_or_comment(lines[stop - 1]) {
            stop -= 1;
        }
        if item_key(&lines[start..stop], indent).as_deref() == Some(key) {
            return Some(start..stop);
        }
    }
    None
}

/// An item's first trigger, or its regex, read by parsing the item on its own.
fn item_key(block: &[&str], indent: usize) -> Option<String> {
    let text: String = block
        .iter()
        .map(|l| l.get(indent.min(indent_of(l))..).unwrap_or(""))
        .collect::<Vec<_>>()
        .join("\n");
    let value: serde_norway::Value = serde_norway::from_str(&text).ok()?;
    let item = value.as_sequence()?.first()?.as_mapping()?;
    let get = |name: &str| item.get(serde_norway::Value::String(name.to_string()));
    if let Some(trigger) = get("trigger").and_then(|v| v.as_str()) {
        return Some(trigger.to_string());
    }
    if let Some(first) = get("triggers")
        .and_then(|v| v.as_sequence())
        .and_then(|t| t.first())
    {
        return first.as_str().map(String::from);
    }
    get("regex").and_then(|v| v.as_str()).map(String::from)
}
