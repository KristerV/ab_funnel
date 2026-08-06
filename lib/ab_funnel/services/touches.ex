defmodule AbFunnel.Services.Touches do
  @moduledoc """
  Reads the event log at the grain every funnel calculation actually wants: one row per
  person per event, at the moment they first reached it.

  Three things happen here and nowhere else, because every one of them is a place the
  numbers can quietly go wrong:

    * **Visitors become people.** Events are keyed by browser; a person with a phone and a
      laptop is two browsers. Resolving through `ab_funnel_identities` at read time is what
      makes identifying someone retroactive over everything that browser already did.
    * **Repeats collapse.** Someone who generates three codes reached that step once. Doing
      this in SQL rather than in memory is also what keeps the dashboard's cost flat: a
      person with fifty events becomes ten rows before anything is loaded.
    * **First touch wins.** Both for step position — the second visit's `landing` must not
      drag that step rightward — and for the variant and source a person is filed under.

  Everything downstream is pure functions over what this returns.
  """
  import Ecto.Query

  alias AbFunnel.Assignment
  alias AbFunnel.Experiments
  alias AbFunnel.Resources.Event
  alias AbFunnel.Resources.Identity

  @default_window_days 90

  # Marks a row whose bucket came from the old single `variant` column rather than from
  # `assignments`, so it can be attributed to an experiment once back in Elixir.
  @legacy_key "$legacy"

  @doc """
  `{:ok, %{touches: [...], people: %{...}, since: ~U[...]}}`.

    * `touches` — `%{person: id, event: name, at: first, last: last}`, one per person per
      event. Both ends are kept because gating on an entry event asks two different
      questions of the same row: *where does this step sit in the journey* (the first
      touch) and *did they reach it after entering* (the last).
    * `people` — `person => %{assignments: %{experiment => variant}, source: source}`. The
      source is from their earliest event; each assignment is from the earliest event that
      named *that experiment*, which is not the same thing once a second test starts.

  Options: `:since` (a `DateTime`) or `:window_days`, defaulting to
  `config :ab_funnel, window_days: #{@default_window_days}`.
  """
  def run(opts \\ []) do
    since = since(opts)

    with {:ok, touches} <- load(first_touch_query(since)),
         {:ok, assignments} <- load(first_assignment_query(since)),
         {:ok, sources} <- load(first_source_query(since)) do
      {:ok, %{touches: touches, people: people(assignments, sources), since: since}}
    end
  end

  defp load(query), do: {:ok, AbFunnel.repo().all(query)}

  defp since(opts) do
    case Keyword.get(opts, :since) do
      %DateTime{} = since ->
        since

      _ ->
        days = Keyword.get(opts, :window_days) || window_days()
        DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
    end
  end

  defp window_days do
    Application.get_env(:ab_funnel, :window_days, @default_window_days)
  end

  # `coalesce(person_key, visitor_id)`: a browser nobody ever identified is its own person.
  # Repeated rather than extracted because Ecto has to see the expression in the select,
  # the grouping and the ordering, and a shared macro reads worse than the three copies.
  defp first_touch_query(since) do
    from(e in Event,
      left_join: i in Identity,
      on: i.visitor_id == e.visitor_id,
      where: e.inserted_at >= ^since,
      where: not like(e.event, ^"source:%"),
      group_by: [fragment("coalesce(?, ?)", i.person_key, e.visitor_id), e.event],
      select: %{
        person: fragment("coalesce(?, ?)", i.person_key, e.visitor_id),
        event: e.event,
        at: type(min(e.inserted_at), :utc_datetime_usec),
        last: type(max(e.inserted_at), :utc_datetime_usec)
      }
    )
  end

  # One row per person per experiment: the bucket from the earliest event naming it.
  #
  # First assignment wins because assignment is per browser — someone rolled independently
  # on a phone and a laptop lands in different arms about half the time, and left alone
  # they show up as two half-finished journeys in two different variants, which is
  # precisely the comparison an A/B test exists to make, corrupted.
  #
  # The `jsonb_each_text` expansion is what makes "earliest" mean earliest *per
  # experiment*. Taking the earliest event's map whole would mean every visitor an app
  # already has is absent from the next test it declares — see `assignments_by_person/1`.
  defp first_assignment_query(since) do
    from(e in Event,
      left_join: i in Identity,
      on: i.visitor_id == e.visitor_id,
      inner_lateral_join:
        kv in fragment(
          """
          SELECT key, value FROM jsonb_each_text(
            CASE WHEN ? = '{}'::jsonb
                 THEN jsonb_strip_nulls(jsonb_build_object(?::text, ?))
                 ELSE ? END)
          """,
          e.assignments,
          ^@legacy_key,
          e.variant,
          e.assignments
        ),
      on: true,
      where: e.inserted_at >= ^since,
      distinct: [
        asc: fragment("coalesce(?, ?)", i.person_key, e.visitor_id),
        asc: kv.key
      ],
      order_by: [asc: e.inserted_at],
      select: %{
        person: fragment("coalesce(?, ?)", i.person_key, e.visitor_id),
        experiment: kv.key,
        variant: kv.value,
        at: e.inserted_at
      }
    )
  end

  defp first_source_query(since) do
    from(e in Event,
      left_join: i in Identity,
      on: i.visitor_id == e.visitor_id,
      where: e.inserted_at >= ^since,
      where: like(e.event, ^"source:%"),
      distinct: [asc: fragment("coalesce(?, ?)", i.person_key, e.visitor_id)],
      order_by: [asc: e.inserted_at],
      select: %{
        person: fragment("coalesce(?, ?)", i.person_key, e.visitor_id),
        event: e.event
      }
    )
  end

  defp people(assignments, sources) do
    sources =
      Map.new(sources, fn row ->
        {row.person, String.replace_leading(row.event, "source:", "")}
      end)

    assignments
    |> assignments_by_person()
    |> Map.new(fn {person, person_assignments} ->
      {person,
       %{
         assignments: person_assignments,
         source: Map.get(sources, person, "direct")
       }}
    end)
  end

  # Earliest wins, per experiment — `Map.put_new` over rows in time order.
  #
  # Per experiment, not per person, is the whole point. A person's first *event* only
  # names the experiments running when they fired it; anything declared afterwards appears
  # on their later events. Keyed off the first event alone, every visitor an app already
  # has would be silently absent from the next test it starts, which is precisely when a
  # second experiment gets declared.
  defp assignments_by_person(rows) do
    rows
    |> Enum.sort_by(& &1.at, DateTime)
    |> Enum.reduce(%{}, fn row, acc ->
      case experiment_key(row) do
        nil ->
          acc

        key ->
          Map.update(acc, row.person, %{key => row.variant}, &Map.put_new(&1, key, row.variant))
      end
    end)
  end

  # Events written before experiments existed carry a variant and no assignments; the query
  # tags those with `@legacy_key`. Rather than rewrite the table, they are attributed at
  # read time to whichever experiment declares a variant by that name.
  defp experiment_key(%{experiment: @legacy_key, variant: variant}) do
    case Experiments.owning(variant) do
      nil -> nil
      experiment -> experiment.key
    end
  end

  defp experiment_key(%{experiment: experiment}), do: experiment

  @doc """
  This person's variant in `experiment`, or `nil` if they were never in it.

  Someone who forced their own bucket with `?ab_funnel=` is treated as not in it at all —
  a developer clicking through their own test must not land in the numbers.
  """
  def variant_in(%{assignments: assignments}, experiment_key) do
    if Assignment.qa?(assignments), do: nil, else: Map.get(assignments, experiment_key)
  end
end
