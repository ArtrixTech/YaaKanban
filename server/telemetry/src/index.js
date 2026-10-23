// YaaKanban telemetry endpoint: POST /v1/daily with one report; stores one row per install per
// day in D1. No IP address or header other than the body is stored.
import { MAX_BODY, validate } from "./validate.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/v1/daily") return new Response("not found", { status: 404 });
    if (request.method !== "POST") return new Response("method not allowed", { status: 405 });
    const text = await request.text();
    if (text.length > MAX_BODY) return new Response("too large", { status: 413 });
    let body;
    try { body = JSON.parse(text); } catch { return new Response("bad json", { status: 400 }); }
    const { row, error } = validate(body);
    if (error) return new Response(error, { status: 400 });
    // A resend of the same day replaces the earlier row.
    await env.DB.prepare(
      `INSERT OR REPLACE INTO daily (install_id, day, received_at, app, build, os, arch, lang, report)
       VALUES (?1, ?2, datetime('now'), ?3, ?4, ?5, ?6, ?7, ?8)`,
    ).bind(row.install_id, row.day, row.app, row.build, row.os, row.arch, row.lang, row.report).run();
    return new Response(null, { status: 204 });
  },
};
