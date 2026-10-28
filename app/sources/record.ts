#!/usr/bin/env bun
/**
 * Record: a source that keeps what you send and type, one JSON line each (docs/sources.md).
 *
 *   RECORD_TOKEN=secret bun sources/record.ts [--port 2590] [--out record.jsonl]
 */
import { appendFile } from "node:fs/promises";
import { parseArgs } from "node:util";

/** What Hex sends as you type. */
export interface Update {
  readonly field: string;
  readonly before: string;
  readonly after: string;
  readonly by: "keyboard" | "app";
  readonly kind: string;
  readonly returnKey: string;
  readonly at: string;
}

/** What a Shortcuts automation sends when you open an app (its name) or leave it (empty). */
export interface AppOpened {
  readonly app: string;
}

export interface Entry {
  readonly at: string;
  /** `sent`: the app emptied the field after you typed in it. `typed`: you left a field with text you typed. */
  readonly event: "sent" | "typed";
  readonly text: string;
  readonly app?: string;
  readonly kind: string;
  readonly returnKey: string;
}

/** The newest update and the app it was in, whether you typed in its field since the last entry, and the app now. */
export interface State {
  readonly last: { readonly update: Update; readonly app: string } | null;
  readonly typed: boolean;
  readonly app: string;
}

export const start: State = { last: null, typed: false, app: "" };

const text = (update: Update) => update.before + update.after;

const entry = ({ update, app }: NonNullable<State["last"]>, event: Entry["event"]): Entry => ({
  at: update.at,
  event,
  text: text(update),
  ...(app && { app }),
  kind: update.kind,
  returnKey: update.returnKey,
});

export const record = (state: State, input: Update | AppOpened): { state: State; entry: Entry | null } => {
  if (!("field" in input)) return { state: { ...state, app: input.app }, entry: null };
  const { last, typed, app } = state;
  const settled = last !== null && typed && text(last.update) !== "";
  const sent = settled && last.update.field === input.field && input.by === "app" && text(input) === "";
  const left = settled && last.update.field !== input.field;

  return {
    state: {
      last: { update: input, app },
      typed: input.by === "keyboard" || (!sent && last?.update.field === input.field && typed),
      app,
    },
    entry: sent ? entry(last, "sent") : left ? entry(last, "typed") : null,
  };
};

if (import.meta.main) {
  const { values } = parseArgs({
    options: { port: { type: "string", default: "2590" }, out: { type: "string", default: "record.jsonl" } },
  });
  const token = process.env["RECORD_TOKEN"];
  let state = start;

  Bun.serve({
    hostname: "127.0.0.1",
    port: Number(values.port),
    fetch: async (request) => {
      if (request.method !== "POST") return new Response(null, { status: 405 });
      if (token && request.headers.get("authorization") !== `Bearer ${token}`) return new Response(null, { status: 401 });
      const result = record(state, (await request.json()) as Update | AppOpened);
      state = result.state;
      if (result.entry) await appendFile(values.out, `${JSON.stringify(result.entry)}\n`);
      return Response.json({});
    },
  });
}
