# Designing a ratio metric that survives idle time: leverage

## Summary
How YaaKanban's leverage (agent work per hour of the user) was reworked so background waits stop
inflating it, days and people compare, and the live figure moves the way the user feels. The
method (anchor scenarios, replay over real data, one shared constant per decision) applies to any
"output ÷ human time" metric.

## Content

### Symptoms and their root causes

| Symptom | Root cause |
|---|---|
| An ML training left running overnight gave huge leverage | Held time (turn over, only a background shell left) counted as full agent work |
| A 30-minute day could read 20× | Work while away had no denominator of its own; it divided by tiny present time |
| The sidebar figure fell as the user started working | A cumulative ratio: away lumps sit in the numerator, every present minute grows the denominator |

Two different things were mixed: *agent effort* and *the user's presence*. They still have to be
mixed (the metric judges a person's amplification), so the fix is in how, not whether.

### The model

- Effective work: in-turn work (background agents included) counts 1; held work counts
  τ/(τ+h), τ = 15 min, h = time since the hold began. Integral over [s, e):
  τ·ln((τ+e−h)/(τ+s−h)). Hyperbolic, not exponential: it starts decaying at once (no grace
  period) but gently, and a long run never quite stops counting.
- Leverage = Ep/P + Ea/(P + m), m = 30 min. Ep/Ea is work while present/away, P present time.
  m is a shrinkage prior: it only bites when P is small, so short visits can't multiply away work,
  while full days are almost unaffected.
- Away work is credited to the slice where the absence *began* (departure attribution) and runs
  past the slice end. Leaving work behind is the user's act at that moment; this also stops the
  next morning from inheriting the night.
- The live panel uses a short window (1 h) with present work only: it answers "what am I doing
  now", and its baseline is the mean of hourly values since midnight, like-for-like.

### Rejected options and why

- **Standard workday as denominator** — breaks comparisons between people with different hours.
- **Full-credit grace period before decay** — a discontinuity that rewards gaming the cutoff.
- **Presence floor (e.g. 2 h)** — penalises a short, effective day of delegation.
- **Discounting away work heavily** — penalises good delegation; the product should encourage it.

### Method that worked

1. Write 8–10 *anchor scenarios* with the user's expected ordering (e.g. 30 min + 5 trainings >
   30 min + 1 training; 1 h present with 3 agents must not be pressed down). Every candidate model
   is scored against them before any code.
2. Replay real history (SQLite `activity` + session turns) through each candidate in a throwaway
   script; look at the day distribution (median, max) and at the live figure's behaviour (how
   often it falls while the user works). Numbers for the shipped model: day median 3.55, max 8.6;
   live figure falling-while-working 12.9 %.
3. Let each constant answer one question and be the same for everyone (τ: how fast a wait stops
   counting; m: how much presence it takes before away work counts fully).

### Data pitfalls

- Held state wasn't recorded before; a one-time backfill (`HeldBackfill`) infers it from turn
  intervals (child sessions merged into the parent). It cannot see background *agents* that left
  no child turns, so history may undercount those; live data uses `subagents`.
- Held/working toggles are lane rows inside an already-running lane: every consumer of lane rows
  (segments, longest run, the session timeline) must treat same-lane rows as no change.
- Departure attribution needs rows past the range end: the report fetch extends to the end of an
  absence that crosses it.
