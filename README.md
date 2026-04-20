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

5. Add the plug to every browser-facing pipeline that serves pages you want to track:

```elixir
pipeline :browser do
  # ... existing plugs ...
  plug AbFunnel.Plug.Visitor
end
```

If you have multiple browser pipelines (e.g. a separate `:ad_browser`), add the plug to each — otherwise visitors landing on those routes won't be tracked.

6. Attach the LiveView hook so `visitor_id` / `variant` / `source` are available in `socket.assigns`:

```elixir
live_session :default, on_mount: [AbFunnel.LiveView] do
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

Once `on_mount AbFunnel.LiveView` is attached, tracking is a one-liner:

```elixir
def mount(_params, _session, socket) do
  AbFunnel.track(socket, "landed")
  {:ok, socket}
end

def handle_event("signup", _params, socket) do
  AbFunnel.track(socket, "signed_up", %{plan: "pro"})
  {:noreply, socket}
end
```

### Variant-specific UI

`@ab_funnel_variant` is assigned by the `on_mount` hook:

```heex
<%= if @ab_funnel_variant == "treatment" do %>
  <.new_signup_form />
<% else %>
  <.classic_signup_form />
<% end %>
```

### Managing variants

Set `active: false` on a variant to stop assigning it to new visitors. Existing visitors keep their variant.

```elixir
def variants do
  [
    %{key: :control, label: "Control", active: false},
    %{key: :treatment, label: "Treatment (winner)", active: true}
  ]
end
```

### UTM source tracking

The visitor plug automatically captures `utm_source` and `utm_campaign` query params and fires a `source:<value>` event. The admin dashboard groups funnels by source.

- `?utm_source=linkedin` → source: `linkedin`
- `?utm_campaign=spring` → source: `spring`
- `?utm_source=google&utm_campaign=retarget` → source: `google/retarget`
- No params → source: `direct` (no event fired)

## Admin dashboard

Mount `AbFunnel.AdminLive` behind auth. It shows conversion funnels grouped by variant and source, with step-by-step and total conversion percentages.

Event labels are auto-humanized from event names (`"started_chat"` → `"Started chat"`).

The dashboard ships its own styles (no Tailwind required) and follows `prefers-color-scheme` for light/dark mode.

## License

MIT
