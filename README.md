# AbFunnel

A/B experiments for Phoenix apps. Declare what you are testing, track the steps, and get a
dashboard that refuses to call a winner before the numbers support one.

Small on purpose: two tables, no background jobs, no service to run. Everything is derived
from an append-only event log at read time.

```elixir
defmodule MyApp.ABTests do
  use AbFunnel.Experiments

  def experiments do
    [
      %{
        key: :onboarding,
        variants: [:control, :guided],
        steps: ~w(signed_up completed_profile activated)
      },
      %{key: :pricing, variants: [monthly: 90, annual: 10], goal: "subscribed"}
    ]
  end
end
```

```elixir
AbFunnel.track(socket, "completed_profile")

if AbFunnel.variant(socket, :pricing) == "annual" do
```

## What it does

- **Concurrent experiments.** A visitor is bucketed once per experiment, so a second test
  costs a second bucket rather than the cross product of both tests' arms.
- **Deterministic bucketing**, stored. Reproducible from a visitor id alone; changing the
  weights later does not rebucket people who are already mid-test.
- **People, not browsers.** A person who starts on a phone and finishes on a laptop is one
  person, retroactively, once anything identifies them.
- **Entry gating.** Only people who fired the entry event are in the funnel, and only what
  they did afterwards counts.
- **Declared funnels.** Steps keep their order, render `0` when nobody reached them, and
  exclude events that belong to some other part of the app.
- **Significance, sample size and sample ratio mismatch.** The dashboard says
  *"collecting"*, *"ahead but not big enough to call"*, or *"winner"* — and tells you when
  the split itself is broken.
- **Bot filtering and a QA override** that keeps your own clicks out of the numbers.

## Installation

### With Igniter (recommended)

```bash
mix igniter.install ab_funnel@github:kristerv/ab_funnel
mix ecto.migrate
```

That one command adds the dependency to `mix.exs`, fetches it, creates an experiments
module, writes the config, generates the migration, and prints the remaining steps. Nothing
to edit by hand first.

If the project has no Igniter yet, `mix archive.install hex igniter_new` makes the task
available without adding Igniter as a dependency.

### Manual setup

1. Add the dependency:

```elixir
{:ab_funnel, github: "kristerv/ab_funnel"}
```

2. Create an experiments module — see [Declaring experiments](#declaring-experiments):

```elixir
defmodule MyApp.ABTests do
  use AbFunnel.Experiments

  def experiments do
    [%{key: :onboarding, variants: [:control, :guided]}]
  end
end
```

3. Configure:

```elixir
config :ab_funnel,
  repo: MyApp.Repo,
  experiments: MyApp.ABTests
```

Optional keys, with their defaults:

```elixir
config :ab_funnel,
  window_days: 90,                                # how far back the dashboard reads
  current_user_assign: :current_user,             # where your app puts the signed-in user
  person_key: {MyApp.Analytics, :person_key, 1}   # how to key people, if not by email
```

4. Generate and run the migration:

```bash
mix ab_funnel.gen.migration
mix ecto.migrate
```

5. Add the plug to every browser-facing pipeline that serves pages you want to track,
**after** whatever loads the current user:

```elixir
pipeline :browser do
  # ... existing plugs ...
  plug :load_current_user      # however your app does this
  plug AbFunnel.Plug.Visitor
end
```

Order matters: the plug binds a signed-in browser to its person automatically, and it can
only do that if `conn.assigns.current_user` is already set. Everything else still works if
it isn't — you just have to call `identify/2` yourself.

If you have multiple browser pipelines (e.g. a separate `:ad_browser`), add the plug to
each — otherwise visitors landing on those routes won't be tracked.

6. Attach the LiveView hook, so assignments are available in `socket.assigns`. Same rule —
list it after whatever assigns the current user:

```elixir
live_session :default,
  on_mount: [{MyAppWeb.UserAuth, :mount_current_user}, AbFunnel.LiveView] do
  # your live routes
end
```

Or per-LiveView: `on_mount AbFunnel.LiveView`.

7. Mount the dashboard (behind your own auth). Use a separate scope with no `MyAppWeb`
alias so the library module resolves directly:

```elixir
scope "/admin" do
  pipe_through [:browser, :require_auth]
  live "/ab", AbFunnel.AdminLive
end
```

## Declaring experiments

`key` and `variants` are required. Everything else has a default that does something
sensible.

```elixir
%{
  key: :deck,
  label: "Demo deck",                          # defaults to a humanised key
  variants: [:features, :solving_emails],
  entry: "deck_started",                       # defaults to the first declared step
  goal: "lead_submitted",                      # defaults to the last declared step
  steps: {MyApp.ABTests, :deck_steps, 1},      # or a plain list, or nothing
  mde: 0.2,                                    # the lift worth detecting, for sizing
  since: ~U[2026-08-01 00:00:00Z],             # ignore everything before this
  active: true                                 # false stops new assignments
}
```

### Variants

Three shapes, same meaning with more or less detail:

```elixir
variants: [:control, :treatment]
variants: [monthly: 90, annual: 10]                              # weights are relative
variants: [%{key: :control, label: "Control", control: true},
           %{key: :old, active: false}]                          # retired, still honoured
```

The first assignable variant is the control unless one says `control: true`. Everything
else is compared against it.

`active: false` stops new assignments and keeps honouring whoever already has that variant
— nobody gets rerolled mid-experiment.

### Entry event

**This is the setting that decides whether your funnel means anything.** Without it, every
visitor holding a cookie is in the funnel, including people who never reached the thing you
are testing. A step below the entry point can then have *more* people in it than the entry
point itself, which is where a `200%` step conversion comes from.

With an entry event:

- someone who never fired it is not in the experiment at all;
- everything they did beforehand is trimmed away, so a `signed_in` fired on your landing
  page stops appearing halfway down a checkout funnel;
- no step can exceed the entry count.

It defaults to the first declared step, so declaring `steps` usually means you get this for
free.

### Steps

An ordered list of event names, a `{Module, :fun, 1}`, or a 1-arity function — the last two
take the variant, so two arms can be two genuinely different journeys:

```elixir
steps: {__MODULE__, :deck_steps, 1}

def deck_steps(variant) do
  slides = variant |> MyApp.Deck.slides() |> Enum.map(&"slide_#{&1}")
  ["deck_started"] ++ slides ++ ["deck_completed", "cta_clicked", "lead_submitted"]
end
```

Declaring steps buys three things: the order is yours, a step nobody reached renders as
`0` instead of vanishing from the chart, and events that are not part of this funnel are
excluded from it.

Leave `steps` out and the order is *inferred* — each event placed at the average position
people first reach it. That works for one linear journey and not much else: two events that
fire together tie, and an event fired elsewhere in the app lands wherever its unrelated
callers put it.

## Usage

### Tracking events

`track/2` takes a socket or a conn, so the same call works everywhere:

```elixir
def mount(_params, _session, socket) do
  AbFunnel.track(socket, "deck_started")
  {:ok, socket}
end

def handle_event("signup", _params, socket) do
  AbFunnel.track(socket, "signed_up", %{plan: "pro"})
  {:noreply, socket}
end

def create(conn, params) do            # controllers too
  AbFunnel.track(conn, "checked_out")
  # ...
end
```

Each event records every bucket the visitor is in at the time, so one call feeds every
running experiment.

Two things are deliberately quiet rather than loud:

- Tracking without a visitor — an endpoint outside the browser pipeline, a background job,
  a crawler — returns `{:ok, :no_visitor}` rather than raising in the middle of whatever you
  were doing.
- Tracking from a LiveView's *disconnected* mount returns `{:ok, :not_connected}` and
  writes nothing. A LiveView mounts twice; without this, every event tracked in `mount/3`
  lands in the table twice.

### Variant-specific UI

```elixir
if AbFunnel.variant(socket, :pricing) == "annual" do
```

```heex
<%= if @ab_funnel_variant == "treatment" do %>
  <.new_signup_form />
<% else %>
  <.classic_signup_form />
<% end %>
```

`@ab_funnel_variant` is the *first* declared experiment's variant, which is the only one
there is in an app running a single test. `@ab_funnel_assignments` holds all of them.

A person is reported under the variant they were assigned **first**, resolved *per
experiment*. Assignment is per browser, so someone on a phone and a laptop is bucketed
twice and lands in different arms around half the time — reporting them under both would
split real journeys across the two arms you are trying to compare.

Per experiment matters when you start a second test on a live app: a visitor who has been
around for months is assigned into the new experiment on their next request, and counted in
it from then on, without disturbing the arm they already hold in the first.

### Previewing a variant

```
/pricing?ab_funnel=pricing:annual     # force a bucket, sticks for the session
/pricing?ab_funnel=off                # back to your real assignment
```

Only variants you actually declare are accepted, so this is not a way for a visitor to
write arbitrary values into your events table. Anyone using it is flagged, and **the report
excludes them entirely** — otherwise the person most likely to force a bucket would be the
one reading the numbers.

### Identifying people across devices

A visitor id identifies a *browser*, not a person. The moment a funnel crosses a login
boundary that matters: someone who generates something on their phone and then clicks a
magic link on their laptop is two visitors, and neither of them completes the funnel.

**Signed-in visitors are bound automatically.** The plug and the `on_mount` hook do it
whenever `current_user` is present, so there is nothing to call and nothing to forget. The
key defaults to a hash of `current_user.email`, falling back to `id`.

The one case nothing can infer is someone who has handed over an email but **does not have
an account yet** — the magic-link signup that is about to happen on their laptop. Bind them
explicitly:

```elixir
AbFunnel.identify_by_email(socket, email)
```

Skip that and everything they did before signing up stays attached to nobody. It is the
only identity call a typical app writes.

Two things follow from how this works:

- **It is retroactive.** Events are never rewritten — the report resolves visitor ids
  through the bindings at read time. Identifying a visitor pulls in everything that browser
  already did, including events recorded before you added the call.
- **It is not precognitive.** A browser that never identifies stays its own person forever.
  Two anonymous visits on two devices are genuinely indistinguishable, so the top of a
  funnel is counted per browser and the tail per person.

Last write wins, so a corrected email replaces a typo. The cost is that on a genuinely
shared browser, person 2 identifying takes person 1's history with them.

### UTM source tracking

The visitor plug captures `utm_source` and `utm_campaign` on the request that first brings
someone in, and fires a single `source:<value>` event.

- `?utm_source=linkedin` → source: `linkedin`
- `?utm_campaign=spring` → source: `spring`
- `?utm_source=google&utm_campaign=retarget` → source: `google/retarget`
- No params → source: `direct` (no event fired)

The value sticks to the visitor for a year, but the event is written **once** — their later
page views do not re-record it. Values arrive from the URL, so they are lowercased, stripped
to `a-z0-9._-`, and capped at 48 characters. A campaign that scrubs down to nothing is
treated as `direct`.

The dashboard breaks a funnel out by source only when there is more than one, because
splitting a small experiment by traffic source turns one thin funnel into several
meaningless ones.

### Bots

Crawlers, uptime checks and link-preview fetchers land on the page, get bucketed, and fire
whatever the top of the funnel tracks. They never reach the bottom.

Requests with a recognisable bot user agent get no cookies, no visitor id and therefore no
events; they render on the control arm. Nothing to configure.

## The dashboard

Mount `AbFunnel.AdminLive` behind auth. Per experiment it shows:

**An arms table** — exposure, conversions, rate, relative lift and confidence for each
variant against the control. Counts are people, not events: someone who generates three
codes counts once at that step.

**A verdict**, which is the part that matters:

| | |
|---|---|
| *Collecting* | An arm is under 30 people. No rate means anything yet. |
| *No significant difference yet* | Past the minimum, under the target size. |
| *X is ahead, but not big enough to call* | `p < 0.05` **and** under the sample size the experiment was designed for. |
| *X wins* | `p < 0.05` **and** past that sample size. |
| *Ran to size, no difference found* | A real result. Ship the simpler one. |

The distinction between the last three is the point. Watch any two arms long enough and one
of them crosses `p < 0.05` by chance; that is why experiments "win" and then fail to
replicate. The required sample size comes from the control's own conversion rate and the
`mde` you declared, and is shown as a progress bar.

**A sample ratio mismatch alarm**, above everything else. If a 50/50 test ran 40/60,
something is splitting traffic unevenly — a redirect, a cache, a bot, an entry event only
one arm fires — and no conversion analysis on top of it is worth reading. Checked at
`p < 0.001`, because it runs on every page load and a looser threshold would cry wolf.

**The funnels**, one per variant, with step-by-step and total conversion, broken out by
source when there is more than one.

Everything the dashboard renders comes from `AbFunnel.Services.Report.run/1`, which is
equally usable from a mix task or a nightly digest:

```elixir
{:ok, report} = AbFunnel.report()
{:ok, report} = AbFunnel.report(window_days: 30, include_inactive: true)
```

The dashboard ships its own styles (no Tailwind required) and follows
`prefers-color-scheme`.

## Upgrading

**From the pre-experiments version.** Nothing you have written needs to change. A module
doing `use AbFunnel.Variants` still works and is read as a single unnamed experiment,
`config :ab_funnel, variants: MyApp.ABVariants` is still honoured, existing events still
report, and browsers holding an `ab_funnel_variant` cookie keep their variant rather than
being rerolled at deploy time.

One migration is needed, because events now carry a bucket per experiment:

```bash
mix ab_funnel.gen.migration --upgrade
mix ecto.migrate
```

It adds a column and relaxes a `NOT NULL`; nothing is rewritten, so it is safe on a live
table.

To move to named experiments, replace `use AbFunnel.Variants` with `use
AbFunnel.Experiments` and point config at `:experiments`. Old events are attributed to the
first experiment that declares a variant by their name, so a single-experiment app carries
its history across with no further work.

**Adding identity support to an older install.** `AbFunnel.Migrations.up/0` creates both
tables, so a fresh install needs nothing extra. An app that predates identity support has
only the events table:

```elixir
def up, do: AbFunnel.Migrations.create_identities()
def down, do: AbFunnel.Migrations.drop_identities()
```

**Adding the event time index.** New installs get it from `Migrations.up/0`:

```elixir
def up, do: AbFunnel.Migrations.create_event_time_index()
def down, do: AbFunnel.Migrations.drop_event_time_index()
```

## Deliberately not here

- **Targeting and audiences** (country, plan, feature flags as a product). This is an
  experiment framework, not a flag service — branch in your own code.
- **Bayesian analysis, CUPED, sequential testing.** More statistical power for more
  machinery; the sample-size guard covers the failure these prevent.
- **Mutual exclusion groups.** Two experiments interfering enough to need one is rare at
  the scale this is built for, and the fix is usually to run them in sequence.
- **Server-side or edge assignment.** Assignment happens in the plug, which means it needs
  a request.

## Housekeeping

The report reads the last `window_days` (default 90). For an app that wants the table
bounded on disk as well:

```elixir
AbFunnel.Services.Events.prune(365)
```

## License

MIT
