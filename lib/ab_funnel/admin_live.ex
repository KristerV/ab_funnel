defmodule AbFunnel.AdminLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    events = AbFunnel.Events.all()
    counts = build_counts(events)
    {:ok, assign(socket, counts: counts)}
  end

  defp build_counts(events) do
    step_order = derive_step_order(events)
    source_lookup = build_source_lookup(events)

    funnel_events = Enum.reject(events, &String.starts_with?(&1.event, "source:"))

    funnel_events
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

  defp build_source_lookup(events) do
    events
    |> Enum.filter(&String.starts_with?(&1.event, "source:"))
    |> Map.new(fn e -> {e.visitor_id, String.replace_leading(e.event, "source:", "")} end)
  end

  defp derive_step_order(events) do
    events
    |> Enum.reject(&String.starts_with?(&1.event, "source:"))
    |> Enum.group_by(& &1.visitor_id)
    |> Enum.flat_map(fn {_vid, visitor_events} ->
      visitor_events
      |> Enum.sort_by(& &1.inserted_at)
      |> Enum.with_index()
      |> Enum.map(fn {e, i} -> {e.event, i} end)
    end)
    |> Enum.group_by(fn {event, _} -> event end, fn {_, i} -> i end)
    |> Enum.map(fn {event, positions} ->
      {event, Enum.sum(positions) / length(positions)}
    end)
    |> Map.new()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-4xl">
        <h1 class="text-2xl font-bold mb-2">A/B Funnel</h1>
        <p class="text-sm text-gray-500 mb-8">Visitor conversion by variant</p>

        <div :for={{variant, sources} <- @counts} class="mt-10">
          <h2 class="text-xl font-bold mb-4">{variant_name(variant)}</h2>

          <div :for={{source, steps} <- sources} class="mb-6 ml-2">
            <div class="flex items-center gap-3 mb-3">
              <h3 class="text-sm font-medium text-gray-500">{source}</h3>
              <span :if={length(steps) >= 2} class="inline-flex items-center rounded-full bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-800">
                {total_conversion(steps)}% total
              </span>
            </div>
            <div class="flex items-center gap-2 overflow-x-auto">
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

        <div :if={@counts == []} class="mt-8 text-center text-gray-500">
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
    <div class="flex items-center gap-2">
      <div class="rounded-lg border bg-white shadow-sm p-4 min-w-[140px] text-center">
        <div class="text-sm text-gray-500 mb-1">{label(@step)}</div>
        <div class="text-2xl font-bold">{@count}</div>
        <div :if={@rate} class="text-xs text-green-600 mt-1">{@rate}%</div>
      </div>
      <div :if={!@last} class="text-gray-300 text-xl">&rarr;</div>
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
