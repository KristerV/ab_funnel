defmodule AbFunnel.Services.Funnel do
  @moduledoc """
  Ordered steps, with a people count on each, for one set of journeys.

  Step order comes from the app when it declares one and is inferred from the data when it
  does not. Those two are not equivalent, and the difference is the whole reason declaring
  is worth it:

    * A **declared** list keeps its order however the data falls, renders a step nobody
      reached as `0` instead of dropping it — which is the one thing a funnel chart exists
      to show — and excludes events that are not part of this funnel. An auth controller
      firing `signed_in` all over the app stops appearing in the middle of a checkout.
    * An **inferred** order places each event at the average position people first reach
      it. That works for a single linear journey and only for that. Two events that fire at
      the same point tie, and an event fired outside the funnel lands wherever its
      unrelated callers happen to put it.
  """

  alias AbFunnel.Experiment
  alias AbFunnel.Experiments

  @doc """
  `{:ok, [%{event:, label:, count:, step_rate:, total_rate:}]}`.

  `journeys` is `%{person => [%{event:, at:}]}`, already gated to the entry event.
  `step_rate` is conversion from the previous step, `total_rate` from the first — both
  `nil` where there is nothing to divide by, so a chart never has to guard.
  """
  def run(%Experiment{} = experiment, variant, journeys) do
    declared = Experiments.steps_for(experiment, variant)
    counts = counts(journeys)
    order = declared || inferred_order(journeys)

    {:ok, build(order, counts, experiment)}
  end

  defp counts(journeys) do
    journeys
    |> Enum.flat_map(fn {_person, touches} -> Enum.map(touches, & &1.event) end)
    |> Enum.frequencies()
  end

  defp build(order, counts, experiment) do
    first = order |> List.first() |> then(&Map.get(counts, &1, 0))

    order
    |> Enum.map(&{&1, Map.get(counts, &1, 0)})
    |> Enum.reduce({[], nil}, fn {event, count}, {acc, previous} ->
      step = %{
        event: event,
        label: label(event, experiment),
        count: count,
        step_rate: rate(count, previous),
        total_rate: rate(count, first)
      }

      {[step | acc], count}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp rate(_count, nil), do: nil
  defp rate(_count, 0), do: nil
  defp rate(count, base), do: count / base

  defp label(event, experiment) do
    if event == experiment.entry do
      Experiments.humanize(event) <> " (entry)"
    else
      Experiments.humanize(event)
    end
  end

  @doc """
  Each event placed at the average position people first reach it.

  Ties are broken by how many people reached the step, most first, then by name. Without
  that the order comes out of `Enum.group_by` and two events that always fire together —
  which is the common case in a tie — swap places between page loads.
  """
  def inferred_order(journeys) do
    positions =
      Enum.flat_map(journeys, fn {_person, touches} ->
        touches
        # `DateTime` as the sorter, not the default: comparing the structs directly falls
        # back to Erlang term order, which ranks their fields alphabetically and so weighs
        # `microsecond` ahead of `minute` and `second`. That silently scrambles the order.
        |> Enum.sort_by(& &1.at, DateTime)
        |> Enum.with_index()
        |> Enum.map(fn {touch, index} -> {touch.event, index} end)
      end)

    positions
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(fn {event, indexes} ->
      {Enum.sum(indexes) / length(indexes), -length(indexes), event}
    end)
    |> Enum.map(&elem(&1, 0))
  end
end
