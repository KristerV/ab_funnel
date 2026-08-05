defmodule AbFunnel.Services.Identities do
  @moduledoc """
  Reading and writing the browser-to-person bindings behind `AbFunnel.Resources.Identity`.
  """
  import Ecto.Query

  alias AbFunnel.Resources.Identity

  @doc """
  Bind a browser to a person.

  Last write wins. A visitor who mistypes their email and retries would otherwise stay
  bound to the typo forever, and rebinding costs nothing because the events are never
  touched. The tradeoff is a genuinely shared browser, where person 2 identifying takes
  person 1's history with them — first-write-wins is wrong in exactly the mirror
  direction, so neither choice is safe and this one at least self-heals the common case.
  """
  def identify(visitor_id, person_key) when is_binary(visitor_id) and is_binary(person_key) do
    %{visitor_id: visitor_id, person_key: person_key}
    |> Identity.changeset()
    |> AbFunnel.repo().insert(
      on_conflict: [set: [person_key: person_key, updated_at: DateTime.utc_now()]],
      conflict_target: :visitor_id
    )
  end

  @doc """
  Every binding, as a `%{visitor_id => person_key}` map ready to resolve events against.
  """
  def lookup do
    from(i in Identity, select: {i.visitor_id, i.person_key})
    |> AbFunnel.repo().all()
    |> Map.new()
  end

  def all do
    AbFunnel.repo().all(Identity)
  end
end
