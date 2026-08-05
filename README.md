# AbFunnel

Lightweight A/B testing for Phoenix LiveView apps. Cookie-based variant assignment, event tracking, and an admin dashboard showing conversion funnels per variant.

## Installation

### With Igniter (recommended)

Add to `mix.exs`:

```elixir
{:ab_funnel, github: "kristerv/ab_funnel"}
```

Then run:

```bash
mix deps.get
mix igniter.install ab_funnel
mix ecto.migrate
```

The installer creates a variants module, adds config, generates the migration, and prints remaining steps (adding the plug + mounting the admin page + attaching the LiveView hook).

### Manual setup

1. Add the dependency:

```elixir
{:ab_funnel, github: "kristerv/ab_funnel"}
```

2. Create a variants module:

```elixir
defmodule MyApp.ABVariants do
  use AbFunnel.Variants

  def variants do
    [
      %{key: :control, label: "Control", active: true},
      %{key: :treatment, label: "Treatment", active: true}
    ]
  end
end
```

3. Configure in `config/config.exs`:

```elixir
config :ab_funnel,
  repo: MyApp.Repo,
  variants: MyApp.ABVariants
```

4. Generate and run the migration:

```bash
mix ab_funnel.gen.migration
mix ecto.migrate
```

5. Add the plug to every browser-facing pipeline that serves pages you want to track, **after** whatever loads the current user:

```elixir
pipeline :browser do
  # ... existing plugs ...
  plug :load_current_user      # however your app does this
  plug AbFunnel.Plug.Visitor
end
```

Order matters: the plug binds a signed-in browser to its person automatically, and it can only do that if `conn.assigns.current_user` is already set. Everything else still works if it isn't — you just have to call `identify/2` yourself.

If you have multiple browser pipelines (e.g. a separate `:ad_browser`), add the plug to each — otherwise visitors landing on those routes won't be tracked.

6. Attach the LiveView hook so `visitor_id` / `variant` / `source` are available in `socket.assigns`. Same rule — list it after whatever assigns the current user:

```elixir
live_session :default,
  on_mount: [{MyAppWeb.UserAuth, :mount_current_user}, AbFunnel.LiveView] do
  # your live routes
end
```

Or per-LiveView: `on_mount AbFunnel.LiveView`.

7. Mount the admin dashboard (behind your own auth). Use a separate scope with no `MyAppWeb` alias so the library module resolves directly:

```elixir
scope "/admin" do
  pipe_through [:browser, :require_auth]
  live "/ab", AbFunnel.AdminLive
end
```

## Usage

### Tracking events

`track/2` takes a socket or a conn, so the same call works everywhere:

```elixir
def mount(_params, _session, socket) do
  AbFunnel.track(socket, "landed")
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

Tracking without a visitor — an endpoint outside the browser pipeline, a background job — returns `{:ok, :no_visitor}` rather than raising in the middle of whatever you were doing.

### Identifying people across devices

A visitor id identifies a *browser*, not a person. The moment a funnel crosses a login
boundary that matters: someone who generates something on their phone and then clicks a
magic link on their laptop is two visitors, and neither of them completes the funnel.

**Signed-in visitors are bound automatically.** The plug and the `on_mount` hook do it
whenever `current_user` is present, so there is nothing to call and nothing to forget.
The key defaults to a hash of `current_user.email`, falling back to `id`:

```elixir
# override for apps keyed on something else
config :ab_funnel, person_key: {MyApp.Analytics, :person_key, 1}

# or if your assign isn't :current_user
config :ab_funnel, current_user_assign: :current_admin
```

The one case nothing can infer is someone who has handed over an email but **does not
have an account yet** — the magic-link signup that is about to happen on their laptop.
Bind them explicitly:

```elixir
AbFunnel.identify_by_email(socket, email)
```

Skip that and everything they did before signing up stays attached to nobody. It is the
only identity call a typical app writes.

Two things follow from how this works:

- **It is retroactive.** Events are never rewritten — `AbFunnel.Services.Report` resolves visitor
  ids through the bindings at read time. Identifying a visitor pulls in everything that
  browser already did, including events recorded before you added the call.
- **It is not precognitive.** A browser that never identifies stays its own person
  forever. Two anonymous visits on two devices are genuinely indistinguishable, so the
  top of a funnel is counted per browser and the tail per person.

Last write wins, so a corrected email replaces a typo. The cost is that on a genuinely
shared browser, person 2 identifying takes person 1's history with them.

### Variant-specific UI

`@ab_funnel_variant` is assigned by the `on_mount` hook:

```heex
<%= if @ab_funnel_variant == "treatment" do %>
  <.new_signup_form />
<% else %>
  <.classic_signup_form />
<% end %>
```

A person is reported under the variant they were assigned **first**. Assignment is a
cookie, so someone on a phone and a laptop is rolled twice and lands in different buckets
around half the time — reporting them under both would split real journeys across the two
arms you are trying to compare. At least one variant must be `active: true`, or there is
nothing to assign and new visitors raise.

### Managing variants

Set `active: false` on a variant to stop assigning it to new visitors. Existing visitors keep their variant — a retired variant is still honoured for whoever already holds it, so nobody gets rerolled mid-experiment.

Variant cookies are validated against your variants module on every request. A cookie
naming something you do not declare is discarded and replaced with a real assignment, so
a visitor cannot pick their own bucket by editing it.

```elixir
def variants do
  [
    %{key: :control, label: "Control", active: false},
    %{key: :treatment, label: "Treatment (winner)", active: true}
  ]
end
```

### UTM source tracking

The visitor plug captures `utm_source` and `utm_campaign` on the request that first
brings someone in, and fires a single `source:<value>` event. The admin dashboard groups
funnels by source.

- `?utm_source=linkedin` → source: `linkedin`
- `?utm_campaign=spring` → source: `spring`
- `?utm_source=google&utm_campaign=retarget` → source: `google/retarget`
- No params → source: `direct` (no event fired)

The value sticks to the visitor for a year, but the event is written **once** — their
later page views do not re-record it.

UTM values arrive from the URL, so they are lowercased, stripped to `a-z0-9._-`, and
capped at 48 characters before being used. A campaign name that scrubs down to nothing is
treated as `direct`.

## Admin dashboard

Mount `AbFunnel.AdminLive` behind auth. It shows conversion funnels grouped by variant and source, with step-by-step and total conversion percentages.

Event labels are auto-humanized from event names (`"started_chat"` → `"Started chat"`).

The dashboard ships its own styles (no Tailwind required) and follows `prefers-color-scheme` for light/dark mode.

Counts are **people, not events** — someone who generates three codes counts once at that
step. Step order is *inferred*, not declared: each event is placed by the average
position at which people first reach it. A linear happy path charts cleanly; a rarely
fired event can land anywhere.

`AbFunnel.Services.Report.funnel/0` returns the same data if you want it outside the dashboard.

## Upgrading

**Adding identity support to an existing install.** `AbFunnel.Migrations.up/0` creates
both tables, so a fresh install needs nothing extra. An app that already ran an earlier
version has the events table and needs only the new one:

```elixir
defmodule MyApp.Repo.Migrations.CreateAbFunnelIdentities do
  use Ecto.Migration

  def up, do: AbFunnel.Migrations.create_identities()
  def down, do: AbFunnel.Migrations.drop_identities()
end
```

Nothing else changes — until you call `identify/2` the table stays empty and every count
falls back to per-browser, exactly as before.

**Adding the event time index.** New installs get it from `Migrations.up/0`. Existing
ones can add it in a migration of their own — nothing queries by time yet, but adding it
later means indexing a table that has been growing for months:

```elixir
def up, do: AbFunnel.Migrations.create_event_time_index()
def down, do: AbFunnel.Migrations.drop_event_time_index()
```

## License

MIT
