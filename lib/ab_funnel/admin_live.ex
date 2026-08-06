defmodule AbFunnel.AdminLive do
  @moduledoc """
  The dashboard. Mount it behind your own auth:

      scope "/admin" do
        pipe_through [:browser, :require_auth]
        live "/ab", AbFunnel.AdminLive
      end

  Everything shown here comes from `AbFunnel.Services.Report.run/1` — this module only
  decides how to say it. The one rule it follows throughout: never present a number as a
  result before it is one. Rates render at any size, verdicts do not.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    {:ok, report} = AbFunnel.Services.Report.run()
    assign(socket, report: report)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      .abf { color-scheme: light dark; padding: 2rem 1rem; font-family: system-ui, -apple-system, sans-serif;
             color: #111827; background: #ffffff; min-height: 100vh; }
      .abf-wrap { max-width: 64rem; margin: 0 auto; }
      .abf h1 { font-size: 1.5rem; font-weight: 700; margin: 0 0 0.25rem; }
      .abf h2 { font-size: 1.125rem; font-weight: 700; margin: 0; }
      .abf h3 { font-size: 0.8125rem; font-weight: 600; margin: 1.25rem 0 0.5rem; color: #6b7280;
                text-transform: uppercase; letter-spacing: 0.04em; }
      .abf-sub { font-size: 0.8125rem; color: #6b7280; margin: 0; }
      .abf-head { display: flex; align-items: baseline; justify-content: space-between; gap: 1rem;
                  margin-bottom: 2rem; flex-wrap: wrap; }
      .abf-refresh { font-size: 0.8125rem; color: #2563eb; background: none; border: 0;
                     cursor: pointer; padding: 0; font-family: inherit; }

      .abf-exp { border: 1px solid #e5e7eb; border-radius: 0.75rem; padding: 1.25rem 1.5rem 1.5rem;
                 margin-bottom: 1.5rem; background: #ffffff; }
      .abf-exp-head { display: flex; align-items: baseline; gap: 0.75rem; flex-wrap: wrap; }
      .abf-meta { font-size: 0.75rem; color: #6b7280; }
      .abf-code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.75rem; }

      .abf-verdict { display: flex; align-items: center; gap: 0.625rem; margin: 1rem 0 0;
                     padding: 0.625rem 0.875rem; border-radius: 0.5rem; font-size: 0.875rem;
                     background: #f3f4f6; color: #374151; }
      .abf-verdict.win { background: #dcfce7; color: #166534; }
      .abf-verdict.warn { background: #fef3c7; color: #92400e; }
      .abf-verdict.alarm { background: #fee2e2; color: #991b1b; }
      .abf-verdict b { font-weight: 600; }

      .abf-progress { margin-top: 0.75rem; }
      .abf-bar { height: 0.375rem; border-radius: 9999px; background: #e5e7eb; overflow: hidden; }
      .abf-bar > div { height: 100%; background: #2563eb; }
      .abf-progress-label { font-size: 0.75rem; color: #6b7280; margin-top: 0.375rem; }

      .abf-table { width: 100%; border-collapse: collapse; margin-top: 1rem; font-size: 0.875rem; }
      .abf-table th { text-align: right; font-weight: 500; color: #6b7280; font-size: 0.75rem;
                      padding: 0 0.5rem 0.5rem; border-bottom: 1px solid #e5e7eb; }
      .abf-table th:first-child, .abf-table td:first-child { text-align: left; }
      .abf-table td { text-align: right; padding: 0.5rem; border-bottom: 1px solid #f3f4f6; }
      .abf-table tr:last-child td { border-bottom: 0; }
      .abf-num { font-variant-numeric: tabular-nums; }
      .abf-up { color: #059669; } .abf-down { color: #dc2626; } .abf-flat { color: #6b7280; }
      .abf-tag { display: inline-block; border-radius: 9999px; background: #f3f4f6; color: #6b7280;
                 padding: 0.0625rem 0.4375rem; font-size: 0.6875rem; margin-left: 0.375rem;
                 vertical-align: 1px; }

      .abf-steps { display: flex; align-items: stretch; gap: 0.5rem; overflow-x: auto; padding-bottom: 0.5rem; }
      .abf-step { display: flex; align-items: center; gap: 0.5rem; }
      .abf-card { border: 1px solid #e5e7eb; background: #ffffff; border-radius: 0.5rem;
                  padding: 0.75rem; min-width: 8.5rem; text-align: center; }
      .abf-card.zero { border-style: dashed; opacity: 0.65; }
      .abf-card-label { font-size: 0.75rem; color: #6b7280; margin-bottom: 0.25rem;
                        white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .abf-card-count { font-size: 1.25rem; font-weight: 700; }
      .abf-card-rate { font-size: 0.6875rem; color: #059669; margin-top: 0.125rem; }
      .abf-arrow { color: #d1d5db; align-self: center; }
      .abf-empty { margin-top: 2rem; text-align: center; color: #6b7280; font-size: 0.875rem; }
      .abf-empty code { display: block; margin-top: 0.75rem; white-space: pre; text-align: left;
                        background: #f3f4f6; padding: 0.75rem; border-radius: 0.5rem;
                        font-size: 0.75rem; overflow-x: auto; }
      .abf details { margin-top: 0.75rem; }
      .abf summary { font-size: 0.75rem; color: #6b7280; cursor: pointer; }

      @media (prefers-color-scheme: dark) {
        .abf { color: #f3f4f6; background: #111827; }
        .abf h3, .abf-sub, .abf-meta, .abf-card-label, .abf-empty, .abf summary,
        .abf-progress-label, .abf-table th { color: #9ca3af; }
        .abf-exp, .abf-card { border-color: #374151; background: #1f2937; }
        .abf-table th { border-bottom-color: #374151; }
        .abf-table td { border-bottom-color: #263244; }
        .abf-verdict { background: #263244; color: #d1d5db; }
        .abf-verdict.win { background: rgba(22, 101, 52, 0.35); color: #86efac; }
        .abf-verdict.warn { background: rgba(146, 64, 14, 0.35); color: #fcd34d; }
        .abf-verdict.alarm { background: rgba(153, 27, 27, 0.35); color: #fca5a5; }
        .abf-bar { background: #374151; }
        .abf-tag, .abf-empty code { background: #263244; color: #9ca3af; }
        .abf-arrow { color: #4b5563; }
        .abf-card-rate { color: #34d399; }
      }
    </style>
    <div class="abf">
      <div class="abf-wrap">
        <div class="abf-head">
          <div>
            <h1>A/B Funnel</h1>
            <p class="abf-sub">
              {@report.people} people since {Calendar.strftime(@report.since, "%b %-d, %Y")}
            </p>
          </div>
          <button class="abf-refresh" phx-click="refresh">Refresh</button>
        </div>

        <.experiment :for={experiment <- @report.experiments} experiment={experiment} />

        <div :if={@report.experiments == []} class="abf-empty">
          No experiments are running.
          <code>config :ab_funnel, experiments: MyApp.ABTests</code>
        </div>
      </div>
    </div>
    """
  end

  defp experiment(assigns) do
    ~H"""
    <div class="abf-exp">
      <div class="abf-exp-head">
        <h2>{@experiment.label}</h2>
        <span class="abf-meta">
          <span :if={@experiment.entry}>
            entry <span class="abf-code">{@experiment.entry}</span> &middot;
          </span>
          <span :if={@experiment.goal}>
            goal <span class="abf-code">{@experiment.goal}</span>
          </span>
          <span :if={is_nil(@experiment.goal)}>no goal event</span>
        </span>
      </div>

      <.srm srm={@experiment.srm} />
      <.verdict verdict={@experiment.verdict} required={@experiment.required_per_arm} />

      <table class="abf-table">
        <thead>
          <tr>
            <th>Variant</th>
            <th>Exposed</th>
            <th>Converted</th>
            <th>Rate</th>
            <th>Lift</th>
            <th>Confidence</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={arm <- @experiment.arms}>
            <td>
              {arm.label}<span :if={arm.control?} class="abf-tag">control</span>
            </td>
            <td class="abf-num">{arm.exposed}</td>
            <td class="abf-num">{arm.converted}</td>
            <td class="abf-num">{percent(arm.rate)}</td>
            <td class={["abf-num", lift_class(arm)]}>{lift(arm)}</td>
            <td class="abf-num abf-meta">{confidence(arm)}</td>
          </tr>
        </tbody>
      </table>

      <div :for={funnel <- @experiment.funnels}>
        <h3>{funnel.label} &middot; {funnel.people} people</h3>
        <.steps steps={funnel.steps} />

        <details :if={funnel.sources != []}>
          <summary>By source</summary>
          <div :for={source <- funnel.sources}>
            <h3>{source.source} &middot; {source.people} people</h3>
            <.steps steps={source.steps} />
          </div>
        </details>
      </div>

      <p :if={@experiment.funnels == []} class="abf-meta">
        Nobody has entered this funnel yet.
      </p>
    </div>
    """
  end

  defp steps(assigns) do
    ~H"""
    <div class="abf-steps">
      <div :for={{step, i} <- Enum.with_index(@steps)} class="abf-step">
        <div class={["abf-card", step.count == 0 && "zero"]}>
          <div class="abf-card-label" title={step.event}>{step.label}</div>
          <div class="abf-card-count">{step.count}</div>
          <div :if={step.step_rate} class="abf-card-rate">{percent(step.step_rate)}</div>
        </div>
        <div :if={i < length(@steps) - 1} class="abf-arrow">&rarr;</div>
      </div>
    </div>
    """
  end

  # Shown before anything else, because a broken split invalidates everything under it.
  defp srm(assigns) do
    ~H"""
    <div :if={not @srm.ok?} class="abf-verdict alarm">
      <b>Sample ratio mismatch.</b>
      The arms are not the sizes they were meant to be (p={format_p(@srm.p_value)}). Something is
      splitting traffic unevenly &mdash; a redirect, a cache, a bot, or an entry event that only
      one arm fires. Fix it before reading anything below.
    </div>
    """
  end

  defp verdict(%{verdict: %{state: :no_goal}} = assigns) do
    ~H"""
    <div class="abf-verdict">
      Nothing to measure yet. Declare a <span class="abf-code">goal</span>
      (or a <span class="abf-code">steps</span> list, whose last entry becomes one).
    </div>
    """
  end

  defp verdict(assigns) do
    ~H"""
    <div class={["abf-verdict", verdict_class(@verdict.state)]}>
      <span>{verdict_message(@verdict)}</span>
    </div>
    <div :if={@verdict.progress && @required} class="abf-progress">
      <div class="abf-bar"><div style={"width: #{Float.round(@verdict.progress * 100, 1)}%"}></div></div>
      <div class="abf-progress-label">
        {@required} people per arm needed to call a result this size.
      </div>
    </div>
    """
  end

  defp verdict_class(:winner), do: "win"
  defp verdict_class(:leading), do: "warn"
  defp verdict_class(_), do: nil

  defp verdict_message(%{state: :winner, leader: leader}) do
    "#{leader.label} wins — #{lift(leader)} lift, and the experiment has reached the size it needs."
  end

  defp verdict_message(%{state: :leading, leader: leader}) do
    "#{leader.label} is ahead at #{confidence(leader)}, but the experiment is not big enough " <>
      "to call yet. Watch a coin flip long enough and it crosses 95% too."
  end

  defp verdict_message(%{state: :no_difference}),
    do: "Ran to size, no difference found. That is a result — ship the simpler one."

  defp verdict_message(%{state: :collecting}),
    do: "Collecting. Too few people in an arm for a rate to mean anything."

  defp verdict_message(%{state: :inconclusive}),
    do: "No significant difference yet."

  defp percent(nil), do: "—"
  defp percent(rate), do: "#{Float.round(rate * 100, 1)}%"

  defp lift(%{comparison: nil}), do: "—"
  defp lift(%{comparison: %{uplift: nil}}), do: "—"

  defp lift(%{comparison: %{uplift: uplift}}) do
    "#{if uplift >= 0, do: "+", else: ""}#{Float.round(uplift * 100, 1)}%"
  end

  defp lift(_), do: "—"

  defp lift_class(%{comparison: %{uplift: uplift}}) when is_number(uplift) do
    cond do
      uplift > 0.001 -> "abf-up"
      uplift < -0.001 -> "abf-down"
      true -> "abf-flat"
    end
  end

  defp lift_class(_), do: "abf-flat"

  defp confidence(%{comparison: %{p_value: p}}) when is_number(p) do
    "#{Float.round((1 - p) * 100, 1)}%"
  end

  defp confidence(_), do: "—"

  defp format_p(p) when is_number(p), do: :erlang.float_to_binary(p * 1.0, decimals: 4)
  defp format_p(_), do: "—"
end
