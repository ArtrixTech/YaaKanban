import assert from "node:assert/strict";
import test from "node:test";
import { validate } from "../src/validate.js";

const now = new Date("2026-10-23T08:00:00Z");
const good = () => ({
  schema: 1, install_id: "e617184b-ea01-4296-a57c-3a770a5f8ef8", day: "2026-10-22",
  app: "0.1.0", build: "1", os: "15", arch: "arm64", lang: "zh",
  integrations: { "claude-code": "installed", codex: "notDetected" },
  settings: { slim_rail: true, show_panel: false },
  counts: { jump_wave: 3, spool_replay: 0 },
  figures: { "sessions.claude-code": "2-5", agent_hours: "<1", leverage: "1-2", parallel_peak: "100+" },
});

test("accepts a report as the app sends it", () => {
  const { row, error } = validate(good(), now);
  assert.equal(error, undefined);
  assert.equal(row.day, "2026-10-22");
  assert.deepEqual(JSON.parse(row.report), good());
  assert.equal(validate({ ...good(), app: "0.1.0-beta+3" }, now).error, undefined);
});

test("rejects unknown or malformed fields", () => {
  const cases = [
    (b) => { b.cwd = "/Users/x"; },
    (b) => { b.schema = 2; },
    (b) => { b.install_id = "not-a-uuid"; },
    (b) => { b.day = "2026-09-01"; },
    (b) => { b.app = "0.1 beta"; },
    (b) => { b.integrations = { warp: "installed" }; },
    (b) => { b.settings = { slim_rail: "yes" }; },
    (b) => { b.counts = { jump_wave: 1.5 }; },
    (b) => { b.counts = { "Prompt Text": 1 }; },
    (b) => { b.figures = { agent_hours: "3.14159265" }; },
    (b) => { b.figures = { "turns.my project": "1" }; },
    (b) => { b.figures = { agent_hours: "9999999" }; },
    (b) => { b.day = "2026-10-32"; },
  ];
  for (const mutate of cases) {
    const b = good();
    mutate(b);
    assert.ok(validate(b, now).error, JSON.stringify(b));
  }
  assert.ok(validate([], now).error);
});

test("accepts the report the Swift tests produce", async () => {
  const { readFile } = await import("node:fs/promises");
  const body = JSON.parse(await readFile(new URL("./fixture-report.json", import.meta.url), "utf8"));
  assert.equal(validate(body, now).error, undefined);
});
