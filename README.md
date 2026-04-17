# AbFunnel

Lightweight A/B testing for Phoenix LiveView apps. Cookie-based variant assignment, event tracking, and an admin dashboard showing conversion funnels per variant.

## Installation

### With Igniter (recommended)

```elixir
# Add to deps in mix.exs (path dep for local use, or version for hex)
{:ab_funnel, path: "~/code/abtest"}
```

Then run:

```bash
mix deps.get
mix igniter.install ab_funnel
mix ecto.migrate
```

The installer creates a variants module, adds config, generates the migration, and prints remaining steps (adding the plug + mounting the admin page).

### Manual setup

1. Add the dependency:

```elixir
{:ab_funnel, path: "~/code/abtest"}
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

5. Add the plug to your router's `:browser` pipeline:

```elixir
pipeline :browser do
  # ... existing plugs ...
  plug AbFunnel.Plug.Visitor
end
```

6. Mount the admin dashboard (behind your own auth):

```elixir
scope "/admin" do
  pipe_through [:browser, :require_auth]
  live "/ab_funnel", AbFunnel.AdminLive
end
```

## Usage

### Tracking events

In any LiveView, read the session values and track events:

```elixir
def mount(_params, session, socket) do
  visitor_id = session["ab_funnel_visitor_id"]
  variant = session["ab_funnel_variant"]

  AbFunnel.track(visitor_id, "landed", variant)

  {:ok, assign(socket, visitor_id: visitor_id, variant: variant)}
end

def handle_event("signup", _params, socket) do
  AbFunnel.track(socket.assigns.visitor_id, "signed_up", socket.assigns.variant)
  {:noreply, socket}
end
```

### Variant-specific UI

```heex
<%= if @variant == "treatment" do %>
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
