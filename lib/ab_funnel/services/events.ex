defmodule AbFunnel.Services.Events do
  @moduledoc """
  Writing to and reading the raw event log.

  Everything that turns the log into a funnel lives in `AbFunnel.Services.Touches` and
  above; this module only knows about rows.
  """
  import Ecto.Query

  alias AbFunnel.Resources.Event

  @doc """
  Record an event against a visitor, stamped with the buckets they were in.

  `assignments` is `%{experiment => variant}`. A bare variant string is accepted for the
  single-experiment callers that predate experiments, and is attributed the same way old
  rows are.
  """
  def track(visitor_id, event, assignments, metadata \\ %{})

  def track(visitor_id, event, variant, metadata) when is_binary(variant) do
    track(visitor_id, event, assignments_for(variant), metadata)
  end

  def track(visitor_id, event, assignments, metadata) when is_map(assignments) do
    %{
      visitor_id: visitor_id,
      event: event,
      assignments: assignments,
      metadata: metadata
    }
    |> Event.changeset()
    |> AbFunnel.repo().insert()
  end

  defp assignments_for(variant) do
    case AbFunnel.Experiments.owning(variant) do
      nil -> %{}
      experiment -> %{experiment.key => variant}
    end
  end

  @doc "Every event, newest last. For tests and one-off inspection, not for the report."
  def all do
    from(e in Event, order_by: [asc: e.inserted_at]) |> AbFunnel.repo().all()
  end

  @doc "Delete everything older than `days`, for an app that wants the table bounded."
  def prune(days) when is_integer(days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    from(e in Event, where: e.inserted_at < ^cutoff)
    |> AbFunnel.repo().delete_all()
  end
end
