# YaaKanban telemetry Worker

Receives the app's daily reports (`POST /v1/daily`, fields in `docs/telemetry.md`), validates
them strictly (`src/validate.js`), and stores one row per install per day in D1. A resend of the
same day replaces the row. Nothing from the request other than the body is stored.

## Deploy

```sh
cd server/telemetry
npx wrangler@4.20.0 login
npx wrangler@4.20.0 d1 create yaakanban-telemetry     # copy database_id into wrangler.toml
npx wrangler@4.20.0 d1 execute yaakanban-telemetry --remote --file schema.sql
npx wrangler@4.20.0 deploy                             # prints https://yaakanban-telemetry.<you>.workers.dev
```

Then build the release with the endpoint:

```sh
YAAK_TELEMETRY_ENDPOINT=https://yaakanban-telemetry.<you>.workers.dev/v1/daily make app
```

Suggested: a Cloudflare WAF rate-limiting rule on `/v1/daily` (e.g. 20 requests / minute per IP)
against floods. The app sends at most 7 requests per launch.

## Test

`npm test` (Node 18+, no dependencies). `test/fixture-report.json` is written by the Swift tests
(`YAAK_UPDATE_FIXTURES=1 make test`), so this checks that the server accepts what the app sends.
Locally: `npx wrangler@4.20.0 d1 execute yaakanban-telemetry --local --file schema.sql`, then
`npx wrangler@4.20.0 dev --local`.

## Queries

```sql
-- Daily active installs
SELECT day, count(*) FROM daily GROUP BY day ORDER BY day DESC LIMIT 30;
-- Versions in the last 7 days
SELECT app, count(DISTINCT install_id) FROM daily WHERE day >= date('now','-7 day') GROUP BY app;
-- Integrations installed
SELECT j.key AS agent, count(DISTINCT install_id) FROM daily, json_each(report, '$.integrations') j
WHERE j.value = 'installed' AND day >= date('now','-7 day') GROUP BY agent;
-- Feature use in the last 30 days
SELECT j.key, sum(j.value) FROM daily, json_each(report, '$.counts') j
WHERE day >= date('now','-30 day') GROUP BY j.key ORDER BY 2 DESC;
-- Week-1 retention: installs first seen in a week that came back 7–13 days later
WITH first AS (SELECT install_id, min(day) d0 FROM daily GROUP BY install_id)
SELECT strftime('%Y-%W', d0) wk, count(DISTINCT install_id) installs,
  count(DISTINCT CASE WHEN julianday(day) - julianday(d0) BETWEEN 7 AND 13 THEN install_id END) kept
FROM first JOIN daily USING (install_id) GROUP BY wk ORDER BY wk DESC;
```

## Free tier

At one write per install per day, the Workers free plan (100,000 requests / day) and D1 free
limits (5 GB storage; about 100,000 rows written / day) leave headroom for tens of thousands of
daily installs. A report row is about 1 KB. Check Cloudflare's current limits before relying on
these numbers.
