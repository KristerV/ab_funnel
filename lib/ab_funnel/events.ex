defmodule AbFunnel.Events do
  import Ecto.Query

  alias AbFunnel.Event

  def track(visitor_id, event, variant, metadata \\ %{}) do
    %{visitor_id: visitor_id, event: event, variant: variant, metadata: metadata}
    |> Event.changeset()
    |> AbFunnel.repo().insert()
  end

  def all do
    AbFunnel.repo().all(Event)
  end

  def all_by_variant(variant) do
    from(e in Event, where: e.variant == ^variant)
    |> AbFunnel.repo().all()
  end
end
