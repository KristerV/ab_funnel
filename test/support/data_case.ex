defmodule AbFunnel.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Query
      import AbFunnel.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(AbFunnel.TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @start ~U[2026-08-01 12:00:00.000000Z]

  @doc "A timestamp `minute` minutes into the test's imaginary day."
  def at(minute), do: DateTime.add(@start, minute, :minute)

  @doc """
  Write an event straight to the log, with the timestamp under the test's control.

  Step order is derived from when each person reached each step, so insertion order is not
  good enough — the test has to say.
  """
  def record(visitor_id, event, minute, assignments \\ %{}) do
    AbFunnel.TestRepo.insert!(%AbFunnel.Resources.Event{
      visitor_id: visitor_id,
      event: event,
      assignments: assignments,
      metadata: %{},
      inserted_at: at(minute),
      updated_at: at(minute)
    })
  end

  @doc "Record a whole journey: one event per minute, in the order given."
  def journey(visitor_id, events, assignments, start \\ 0) do
    events
    |> Enum.with_index(start)
    |> Enum.each(fn {event, minute} -> record(visitor_id, event, minute, assignments) end)
  end

  @doc """
  Swap the experiments module for one test.

  Application env is global, so anything calling this has to be `async: false`.
  """
  def put_experiments(module) do
    previous = Application.get_env(:ab_funnel, :experiments)
    set_experiments(module)

    ExUnit.Callbacks.on_exit(fn -> set_experiments(previous) end)
  end

  defp set_experiments(nil), do: Application.delete_env(:ab_funnel, :experiments)
  defp set_experiments(module), do: Application.put_env(:ab_funnel, :experiments, module)

  @doc """
  The report over everything the test wrote.

  `since` is pinned rather than left to the rolling window, so a test asserting on fixed
  timestamps does not start failing three months from now.
  """
  def report(opts \\ []) do
    {:ok, report} =
      opts
      |> Keyword.put_new(:since, ~U[2026-07-01 00:00:00.000000Z])
      |> AbFunnel.Services.Report.run()

    report
  end

  @doc "One experiment out of a `Report.run/1` result."
  def experiment(report, key), do: Enum.find(report.experiments, &(&1.key == key))

  @doc "One variant's funnel as `[{event, count}]`, which is what most assertions want."
  def steps(report, experiment_key, variant) do
    report
    |> experiment(experiment_key)
    |> Map.fetch!(:funnels)
    |> Enum.find(&(&1.variant == variant))
    |> case do
      nil -> nil
      funnel -> Enum.map(funnel.steps, &{&1.event, &1.count})
    end
  end

  @doc "One variant's arm — exposure, conversions and significance."
  def arm(report, experiment_key, variant) do
    report
    |> experiment(experiment_key)
    |> Map.fetch!(:arms)
    |> Enum.find(&(&1.variant == variant))
  end
end
