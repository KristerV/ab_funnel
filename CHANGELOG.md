# Changelog

## 0.3.0

Experiments become first-class, and the dashboard stops presenting small numbers as
results. Nothing an existing app has written needs to change — see **Upgrading** below.

### Fixed

- **Everyone holding a cookie was in the funnel.** A step below the entry point could hold
  more people than the entry point itself, which is where a "200% step conversion" came
  from. Declare `entry:` and only people who fired it are in the experiment, counting only
  what they did afterwards.
- **Step order was inferred, globally, from data that could not support it.** Ordering is
  now declared per variant (`steps:`), computed per variant when inferred, and a declared
  step nobody reached renders as `0` rather than vanishing from the chart. Inferred ties
  now break deterministically instead of by map iteration order.
- **The report loaded the whole events table into memory** on every dashboard render.
  Person resolution and first-touch collapsing now happen in SQL, over a rolling window
  (`window_days`, default 90).

### Added

- **Concurrent experiments.** `AbFunnel.Experiments` replaces the single `variants/0` list.
  A visitor is bucketed once per experiment, so a second test costs a second bucket rather
  than the cross product of both tests' arms. Events carry `assignments` — a bucket per
  experiment — instead of one `variant` column.
- **Deterministic bucketing** (SHA-256 of experiment key and visitor id), stored in one
  cookie for all experiments. Reproducible from a visitor id alone; changing weights later
  does not rebucket people already mid-test. Weights: `variants: [monthly: 90, annual: 10]`.
- **`AbFunnel.Stats`** — two-proportion z-test, confidence intervals, required sample size
  from the declared `mde`, and a sample ratio mismatch check.
- **Verdicts that refuse to be read too early.** The dashboard distinguishes *collecting*,
  *ahead but not big enough to call*, *winner*, and *ran to size, found nothing*. A result
  is only called when it is both significant and past the sample size the experiment was
  designed for.
- **Sample ratio mismatch alarm**, shown above everything else. A 50/50 test running 40/60
  is broken, and no analysis on top of it is worth reading.
- **Bot filtering.** Crawlers, uptime checks and link-preview fetchers get no cookies, no
  visitor id and no events. They render on the control arm.
- **QA override.** `?ab_funnel=deck:features` forces a bucket for a look at the other arm;
  `?ab_funnel=off` clears it. Overridden visitors are flagged and excluded from the report.
- **`AbFunnel.variant(socket, :experiment)`**, and `@ab_funnel_assignments` in templates.
- `AbFunnel.report/1` for use outside the dashboard; `Events.prune/1` for bounding the
  table; `mix ab_funnel.gen.migration --upgrade`.

### Changed

- Tracking from a LiveView's disconnected mount is a no-op returning `{:ok, :not_connected}`.
  A LiveView mounts twice; without this every event tracked in `mount/3` was written twice.
- `Events.track/4` takes an assignments map (a bare variant string still works).

### Upgrading

One migration, because events now carry a bucket per experiment:

```bash
mix ab_funnel.gen.migration --upgrade
mix ecto.migrate
```

It adds a column and relaxes a `NOT NULL`. Nothing is rewritten, so it is safe on a live
table.

Everything else keeps working as it is. `use AbFunnel.Variants` is read as a single unnamed
experiment, `config :ab_funnel, variants:` is still honoured, existing events still report,
and browsers holding an `ab_funnel_variant` cookie keep their variant rather than being
rerolled at deploy time.

To move to named experiments, swap `use AbFunnel.Variants` for `use AbFunnel.Experiments`
and point config at `:experiments`. Old events are attributed to the first experiment that
declares a variant by their name, so a single-experiment app carries its history across
with no further work.
