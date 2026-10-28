import { expect, test } from "bun:test";

import { type Entry, type State, type Update, record, start } from "./record.ts";

let clock = 0;
const update = (before: string, by: Update["by"] = "keyboard", field = "a", extra: Partial<Update> = {}): Update => ({
  field,
  before,
  after: "",
  by,
  kind: "text",
  returnKey: "default",
  at: `2026-10-20T07:00:${String(clock++).padStart(2, "0")}.000Z`,
  ...extra,
});

const entries = (...updates: ReadonlyArray<Update>): ReadonlyArray<Pick<Entry, "event" | "text">> => {
  let state: State = start;
  const out: Array<Pick<Entry, "event" | "text">> = [];
  for (const next of updates) {
    const result = record(state, next);
    state = result.state;
    if (result.entry) out.push({ event: result.entry.event, text: result.entry.text });
  }
  return out;
};

test("text the app empties after you typed it was sent", () => {
  expect(entries(update("", "app"), update("hey"), update("hey you"), update("", "app"), update("n"))).toEqual([
    { event: "sent", text: "hey you" },
  ]);
});

test("a field you leave with text you typed was typed", () => {
  expect(entries(update("", "app"), update("note"), update("note", "app", "b"), update("x", "keyboard", "b"))).toEqual([
    { event: "typed", text: "note" },
  ]);
});

test("the caret moving keeps what you typed", () => {
  expect(entries(update("", "app"), update("hey"), update("he", "app"), update("", "app"))).toEqual([
    { event: "sent", text: "he" },
  ]);
});

test("text you didn't type is not yours", () => {
  expect(entries(update("draft from before", "app"), update("", "app"), update("", "app", "b"))).toEqual([]);
});

test("text you erase yourself was not sent", () => {
  expect(entries(update("", "app"), update("ugh"), update(""), update("", "app"))).toEqual([]);
});

test("an entry keeps the app Shortcuts said you opened, and the time you last typed it", () => {
  let state: State = start;
  state = record(state, { app: "Messages" }).state;
  state = record(state, update("", "app")).state;
  const typed = update("on my way");
  state = record(state, typed).state;
  state = record(state, { app: "" }).state;
  const { entry } = record(state, update("", "app"));
  expect(entry).toEqual({ at: typed.at, event: "sent", text: "on my way", app: "Messages", kind: "text", returnKey: "default" });
});

test("text typed after you left the app has no app", () => {
  let state: State = record(start, { app: "Messages" }).state;
  state = record(state, { app: "" }).state;
  state = record(state, update("", "app")).state;
  state = record(state, update("hi")).state;
  expect(record(state, update("", "app")).entry?.app).toBeUndefined();
});
