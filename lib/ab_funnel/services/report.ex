defmodule AbFunnel.Services.Report do
  @moduledoc """
  Turns the raw event log into funnel counts, grouped variant -> source -> ordered steps.

  There is no funnel definition anywhere: step order is *inferred* from the data by
  averaging how far into each person's journey a given step tends to appear. A linear
  happy path falls out cleanly; a rarely-fired event can land anywhere.
  """

  @doc """
  The funnel as `[{variant, [{source, [{event, count}]}]}]`.

  Counts are people, not events — someone who generates three codes counts once.
  """
  def funnel do
    funnel(AbFunnel.Services.Events.all(), AbFunnel.Services.Identities.lookup())
  end

  @doc """
  The same calculation over events and bindings you supply, for tests and for callers
  that already hold the data.
  """
  def funnel(events, aliases) do
    events = resolve_people(events, aliases)
    step_order = step_order(events)
    source_lookup = source_lookup(events)

    events
    |> reject_source_events()
    |> Enum.group_by(& &1.variant)
    |> Enum.map(fn {variant, variant_events} ->
      sources =
        variant_events
        |> Enum.group_by(&Map.get(source_lookup, &1.visitor_id, "direct"))
        |> Enum.map(fn {source, source_events} ->
          steps =
            source_events
            |> Enum.group_by(& &1.event)
            |> Enum.map(fn {event, evts} ->
              {event, evts |> Enum.map(& &1.visitor_id) |> Enum.uniq() |> length()}
            end)
            |> Enum.sort_by(fn {event, _} -> Map.get(step_order, event, 999) end)

          {source, steps}
        end)
        |> Enum.sort_by(fn {source, _} -> source end)

      {variant, sources}
    end)
    |> Enum.sort_by(fn {variant, _} -> variant end)
  end

  @doc """
  Each event name mapped to its average position across the people who reached it.

  Exposed because it is the part most likely to surprise: it is what decides the left to
  right order of the chart.
  """
  def step_order(events) do
    events
    |> reject_source_events()
    |> Enum.group_by(& &1.visitor_id)
    |> Enum.flat_map(fn {_vid, visitor_events} ->
      visitor_events
      # `DateTime` as the sorter, not the default: comparing the structs directly falls
      # back to Erlang term order, which ranks their fields alphabetically and so weighs
      # `microsecond` ahead of `minute` and `second`. That silently scrambles the order.
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      # Position means "when they first reached this step". Without the dedup a second
      # visit puts another `landing` halfway down the list, dragging that step's average
      # rightward and eventually reordering the chart.
      |> Enum.uniq_by(& &1.event)
      |> Enum.with_index()
      |> Enum.map(fn {e, i} -> {e.event, i} end)
    end)
    |> Enum.group_by(fn {event, _} -> event end, fn {_, i} -> i end)
    |> Enum.map(fn {event, positions} -> {event, Enum.sum(positions) / length(positions)} end)
    |> Map.new()
  end

  @doc """
  Swap each event's visitor id for the person it belongs to, and put that whole person on
  a single variant.

  Doing this once, up front, means every count, order and source calculation downstream
  is per-person for free. And because the events themselves are never rewritten, binding
  a visitor applies retroactively to everything that browser already did.

  The variant is rewritten too, because assignment is per browser: a person who lands on
  their phone and finishes on their laptop is rolled independently on each and lands in
  different buckets around half the time. Left alone they show up as two half-finished
  journeys in two different variants — which is precisely the comparison an A/B test
  exists to make, quietly corrupted. Their first assignment wins.
  """
  def resolve_people(events, aliases) do
    events =
      Enum.map(events, fn e ->
        %{e | visitor_id: Map.get(aliases, e.visitor_id, e.visitor_id)}
      end)

    canonical = canonical_variants(events)

    Enum.map(events, fn e ->
      %{e | variant: Map.get(canonical, e.visitor_id, e.variant)}
    end)
  end

  defp canonical_variants(events) do
    events
    # Newest first, because `Map.new` keeps the last value for a repeated key — so the
    # earliest event, and the variant it was recorded under, is what survives.
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Map.new(fn e -> {e.visitor_id, e.variant} end)
  end

  defp source_lookup(events) do
    events
    |> Enum.filter(&String.starts_with?(&1.event, "source:"))
    # First touch wins. `Map.new` keeps the last value for a repeated key, so feed it
    # newest-first: a person who arrives on two devices has two source events, and the
    # one that brought them in originally is the one worth attributing to.
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Map.new(fn e -> {e.visitor_id, String.replace_leading(e.event, "source:", "")} end)
  end

  defp reject_source_events(events) do
    Enum.reject(events, &String.starts_with?(&1.event, "source:"))
  end
end
