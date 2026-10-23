// Checks a daily report (schema 1, see docs/telemetry.md) and returns the row to store, or an
// error string. Strict on shape and values; count, setting and figure names are only checked by
// pattern, so an app adding one does not need a server release first.

export const MAX_BODY = 8192;

const AGENTS = new Set(["claude-code", "codex", "cursor", "opencode", "pi"]);
const STATUSES = new Set(["installed", "outdated", "notInstalled", "notDetected"]);
const TOP = new Set(["schema", "install_id", "day", "app", "build", "os", "arch", "lang",
  "integrations", "settings", "counts", "figures"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const SHORT = /^[A-Za-z0-9._+-]{1,32}$/;
const KEY = /^[a-z_]{1,40}$/;
const FIGURE_KEY = /^[a-z_]{1,24}(\.[a-z-]{1,16})?$/;
// Telemetry.bucket in Sources/YaaCore/Telemetry.swift.
const BUCKETS = new Set(["0", "1", "2-5", "6-20", "21-100", "100+", "<1", "1-3", "3-8", "8-24", "24+",
  "<0.5", "0.5-1", "1-2", "2-4", "4+"]);

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

function map(v, max, check) {
  if (!isObject(v)) return false;
  const entries = Object.entries(v);
  return entries.length <= max && entries.every(([k, x]) => check(k, x));
}

/** `now` is a Date; a day more than 10 days back or 2 ahead (clock skew) is refused. */
export function validate(body, now = new Date()) {
  if (!isObject(body)) return { error: "not an object" };
  for (const k of Object.keys(body)) if (!TOP.has(k)) return { error: `unknown field ${k}` };
  if (body.schema !== 1) return { error: "schema" };
  if (typeof body.install_id !== "string" || !UUID.test(body.install_id)) return { error: "install_id" };
  if (typeof body.day !== "string" || !DAY.test(body.day)) return { error: "day" };
  const start = new Date(`${body.day}T00:00:00Z`);
  if (isNaN(start) || start.toISOString().slice(0, 10) !== body.day) return { error: "day" };
  const age = (now.getTime() - start.getTime()) / 86_400_000;
  if (!(age >= -2 && age <= 10)) return { error: "day out of range" };
  for (const k of ["app", "build", "os", "arch", "lang"]) {
    if (typeof body[k] !== "string" || !SHORT.test(body[k])) return { error: k };
  }
  if (!map(body.integrations, 16, (k, v) => AGENTS.has(k) && STATUSES.has(v))) return { error: "integrations" };
  if (!map(body.settings, 32, (k, v) => KEY.test(k) && typeof v === "boolean")) return { error: "settings" };
  if (!map(body.counts, 64, (k, v) => KEY.test(k) && Number.isInteger(v) && v >= 0 && v <= 100_000)) return { error: "counts" };
  if (!map(body.figures, 32, (k, v) => FIGURE_KEY.test(k) && BUCKETS.has(v))) return { error: "figures" };
  return {
    row: {
      install_id: body.install_id, day: body.day, app: body.app, build: body.build, os: body.os,
      arch: body.arch, lang: body.lang, report: JSON.stringify(body),
    },
  };
}
