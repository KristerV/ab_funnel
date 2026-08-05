defmodule AbFunnel.AdminLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, counts: AbFunnel.Services.Report.funnel())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      .abf { color-scheme: light dark; padding: 2rem 1rem; font-family: system-ui, -apple-system, sans-serif;
             color: #111827; background: #ffffff; min-height: 100vh; }
      .abf-wrap { max-width: 56rem; margin: 0 auto; }
      .abf h1 { font-size: 1.5rem; font-weight: 700; margin: 0 0 0.5rem; }
      .abf h2 { font-size: 1.25rem; font-weight: 700; margin: 0 0 1rem; }
      .abf h3 { font-size: 0.875rem; font-weight: 500; margin: 0; color: #6b7280; }
      .abf-sub { font-size: 0.875rem; color: #6b7280; margin: 0 0 2rem; }
      .abf-variant { margin-top: 2.5rem; }
      .abf-source { margin: 0 0 1.5rem 0.5rem; }
      .abf-source-head { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.75rem; }
      .abf-badge { display: inline-flex; align-items: center; border-radius: 9999px;
                   background: #dbeafe; color: #1e40af; padding: 0.125rem 0.5rem;
                   font-size: 0.75rem; font-weight: 500; }
      .abf-steps { display: flex; align-items: center; gap: 0.5rem; overflow-x: auto; }
      .abf-step { display: flex; align-items: center; gap: 0.5rem; }
      .abf-card { border: 1px solid #e5e7eb; background: #ffffff; border-radius: 0.5rem;
                  box-shadow: 0 1px 2px rgba(0,0,0,0.05); padding: 1rem; min-width: 140px; text-align: center; }
      .abf-card-label { font-size: 0.875rem; color: #6b7280; margin-bottom: 0.25rem; }
      .abf-card-count { font-size: 1.5rem; font-weight: 700; }
      .abf-card-rate { font-size: 0.75rem; color: #059669; margin-top: 0.25rem; }
      .abf-arrow { color: #d1d5db; font-size: 1.25rem; }
      .abf-empty { margin-top: 2rem; text-align: center; color: #6b7280; }
      @media (prefers-color-scheme: dark) {
        .abf { color: #f3f4f6; background: #111827; }
        .abf h3, .abf-sub, .abf-card-label, .abf-empty { color: #9ca3af; }
        .abf-badge { background: rgba(30, 64, 175, 0.4); color: #bfdbfe; }
        .abf-card { border-color: #374151; background: #1f2937; }
        .abf-card-rate { color: #34d399; }
        .abf-arrow { color: #4b5563; }
      }
    </style>
    <div class="abf">
      <div class="abf-wrap">
        <h1>A/B Funnel</h1>
        <p class="abf-sub">Visitor conversion by variant</p>

        <div :for={{variant, sources} <- @counts} class="abf-variant">
          <h2>{variant_name(variant)}</h2>

          <div :for={{source, steps} <- sources} class="abf-source">
            <div class="abf-source-head">
              <h3>{source}</h3>
              <span :if={length(steps) >= 2} class="abf-badge">
                {total_conversion(steps)}% total
              </span>
            </div>
            <div class="abf-steps">
              <.step_card
                :for={{{step, count}, i} <- Enum.with_index(steps)}
                step={step}
                count={count}
                prev_count={if i > 0, do: elem(Enum.at(steps, i - 1), 1), else: nil}
                last={i == length(steps) - 1}
              />
            </div>
          </div>
        </div>

        <div :if={@counts == []} class="abf-empty">
          No funnel events recorded yet.
        </div>
      </div>
    </div>
    """
  end

  defp step_card(assigns) do
    rate =
      if assigns.prev_count && assigns.prev_count > 0 do
        Float.round(assigns.count / assigns.prev_count * 100, 1)
      else
        nil
      end

    assigns = assign(assigns, :rate, rate)

    ~H"""
    <div class="abf-step">
      <div class="abf-card">
        <div class="abf-card-label">{label(@step)}</div>
        <div class="abf-card-count">{@count}</div>
        <div :if={@rate} class="abf-card-rate">{@rate}%</div>
      </div>
      <div :if={!@last} class="abf-arrow">&rarr;</div>
    </div>
    """
  end

  defp total_conversion(steps) do
    {_, first} = List.first(steps)
    {_, last} = List.last(steps)
    if first > 0, do: Float.round(last / first * 100, 1), else: 0.0
  end

  defp variant_name(key) do
    AbFunnel.variants_module().name(key)
  end

  defp label("source:" <> source), do: source

  defp label(event) do
    event
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
