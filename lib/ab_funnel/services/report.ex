defmodule AbFunnel.Services.Report do
  @moduledoc """
  Every running experiment, measured.

  Reads the log once — the expensive part — and then runs each experiment over the same
  person-grain data. Two tests cost one set of queries.

  `AbFunnel.AdminLive` renders this; nothing in it is display logic, so it is equally
  usable from a mix task, a nightly digest, or a test.
  """

  alias AbFunnel.Experiments
  alias AbFunnel.Services.ExperimentReport
  alias AbFunnel.Services.Touches

  @doc """
  `{:ok, %{experiments: [...], since: ~U[...], generated_at: ~U[...]}}`.

  Options are passed to `AbFunnel.Services.Touches.run/1` (`:since`, `:window_days`), plus
  `:include_inactive` to report on experiments that have been switched off.
  """
  def run(opts \\ []) do
    with {:ok, data} <- Touches.run(opts),
         {:ok, experiments} <- experiments(opts),
         {:ok, reports} <- measure(experiments, data) do
      {:ok,
       %{
         experiments: reports,
         since: data.since,
         people: map_size(data.people),
         generated_at: DateTime.utc_now()
       }}
    end
  end

  defp experiments(opts) do
    case Keyword.get(opts, :include_inactive, false) do
      true -> {:ok, Experiments.all()}
      false -> {:ok, Experiments.active()}
    end
  end

  defp measure(experiments, data) do
    {:ok,
     Enum.map(experiments, fn experiment ->
       {:ok, report} = ExperimentReport.run(experiment, data)
       report
     end)}
  end
end
