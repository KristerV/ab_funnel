defmodule AbFunnel.Experiments do
  @moduledoc """
  Where the app declares what it is testing.

      defmodule MyApp.ABTests do
        use AbFunnel.Experiments

        def experiments do
          [
            %{
              key: :deck,
              variants: [:features, :solving_emails],
              entry: "deck_started",
              goal: "lead_submitted",
              steps: {__MODULE__, :deck_steps, 1}
            },
            %{key: :pricing, variants: [monthly: 90, annual: 10]}
          ]
        end
      end

  Experiments are independent: a visitor is bucketed once per experiment, so two tests run
  side by side without declaring the cross product of their arms. That is the whole reason
  this exists rather than a single `variants/0` list.

  Every field but `key` and `variants` is optional:

    * `entry` — the event that puts someone *in* the funnel. Without it, anyone holding a
      cookie counts, including people who never reached the thing under test, and steps
      downstream of the entry point can exceed it. Defaults to the first declared step.
    * `goal` — the event that counts as a conversion, which is what significance is
      computed on. Defaults to the last declared step.
    * `steps` — an ordered list of event names, or `{Module, :fun, 1}` / a 1-arity function
      taking the variant and returning one. Declared steps keep their order, render as `0`
      when nobody reached them, and drop events that are not part of this funnel. Without
      it the order is *inferred* from the data, which only works for a linear journey.
    * `since` — ignore everything before this moment. For restarting a test without
      dropping the table.
    * `mde` — the relative lift worth detecting, used to size the experiment. `0.2` means
      "tell me when it moves 20%".
    * `active` — `false` stops new assignments and hides it from the dashboard.

  Variants accept three shapes, which mean the same thing with more or less detail:

      variants: [:control, :treatment]
      variants: [control: 90, treatment: 10]                    # weights
      variants: [%{key: :control, label: "Control", weight: 1, control: true}]

  The first variant is the control unless one says `control: true`.
  """

  alias AbFunnel.Experiment

  @callback experiments() :: [map()]

  defmacro __using__(_opts) do
    quote do
      @behaviour AbFunnel.Experiments
    end
  end

  @doc "Every declared experiment, normalised."
  def all do
    module().experiments() |> Enum.map(&normalise/1)
  end

  @doc "The ones still running."
  def active, do: Enum.filter(all(), & &1.active?)

  @doc "One experiment by key, or `nil`."
  def fetch(key) when is_binary(key), do: Enum.find(all(), &(&1.key == key))
  def fetch(key) when is_atom(key), do: fetch(Atom.to_string(key))

  @doc """
  The experiment a bare variant name belongs to.

  Events written before experiments existed carry a variant and no experiment, and the
  same is true of a `ab_funnel_variant` cookie set by an older version. Rather than make
  every app configure where that history belongs, it is attributed to the first declared
  experiment that admits a variant by that name — which is the right answer whenever an
  app had one experiment, and every app that upgrades did.
  """
  def owning(variant) when is_binary(variant) do
    Enum.find(all(), &Experiment.known?(&1, variant))
  end

  def owning(_), do: nil

  @doc """
  The declared step order for a variant, or `nil` when the app declares none.

  Resolved per variant rather than once, because two arms of a test are frequently two
  different journeys — that is often the thing being tested.
  """
  def steps_for(%Experiment{steps: nil}, _variant), do: nil

  def steps_for(%Experiment{steps: {module, function, 1}}, variant) do
    module |> apply(function, [variant]) |> normalise_events()
  end

  def steps_for(%Experiment{steps: fun}, variant) when is_function(fun, 1) do
    fun.(variant) |> normalise_events()
  end

  def steps_for(%Experiment{steps: list}, _variant) when is_list(list) do
    normalise_events(list)
  end

  @doc """
  The module holding the declarations.

  Falls back to the older `:variants` key, whose module `use AbFunnel.Variants` teaches to
  answer `experiments/0` with a single unnamed experiment — so an existing install keeps
  working untouched.
  """
  def module do
    case Application.get_env(:ab_funnel, :experiments) ||
           Application.get_env(:ab_funnel, :variants) do
      nil ->
        raise """
        AbFunnel has no experiments module. Declare one and point config at it:

            config :ab_funnel, experiments: MyApp.ABTests
        """

      module ->
        module
    end
  end

  @doc "Fill in every optional field and turn keys into the strings the events table holds."
  def normalise(%Experiment{} = experiment), do: experiment

  def normalise(attrs) when is_map(attrs) do
    key = attrs |> Map.fetch!(:key) |> to_string()

    experiment = %Experiment{
      key: key,
      label: attrs |> Map.get(:label) |> presence() || humanize(key),
      variants: normalise_variants(Map.get(attrs, :variants, [])),
      entry: attrs |> Map.get(:entry) |> maybe_string(),
      goal: attrs |> Map.get(:goal) |> maybe_string(),
      steps: Map.get(attrs, :steps),
      since: Map.get(attrs, :since),
      mde: Map.get(attrs, :mde, 0.2),
      active?: Map.get(attrs, :active, true)
    }

    fill_from_steps(experiment)
  end

  # `entry` and `goal` are the first and last step of the funnel in almost every case, and
  # an app that has already written the list out should not have to say so twice.
  defp fill_from_steps(experiment) do
    control = Experiment.control(experiment)
    steps = control && steps_for(experiment, control.key)

    %{
      experiment
      | entry: experiment.entry || (steps && List.first(steps)),
        goal: experiment.goal || (steps && List.last(steps))
    }
  end

  defp normalise_variants([]), do: []

  defp normalise_variants(variants) do
    variants
    |> Enum.map(&variant_attrs/1)
    |> Enum.map(fn attrs ->
      key = attrs |> Map.fetch!(:key) |> to_string()

      %{
        key: key,
        label: attrs |> Map.get(:label) |> presence() || humanize(key),
        # `active: false` is how the older API retired a variant, and it means the same
        # thing a zero weight does: keep honouring it for whoever already holds it, stop
        # handing it out.
        weight: weight(attrs),
        control?: Map.get(attrs, :control, false)
      }
    end)
    |> mark_control()
  end

  defp variant_attrs(%{} = attrs), do: attrs
  defp variant_attrs(key) when is_atom(key) or is_binary(key), do: %{key: key}
  defp variant_attrs({key, weight}) when is_integer(weight), do: %{key: key, weight: weight}
  defp variant_attrs({key, attrs}) when is_map(attrs), do: Map.put(attrs, :key, key)

  defp weight(attrs) do
    cond do
      Map.get(attrs, :active) == false -> 0
      is_integer(attrs[:weight]) -> max(attrs[:weight], 0)
      true -> 1
    end
  end

  defp mark_control(variants) do
    if Enum.any?(variants, & &1.control?) do
      variants
    else
      # The first arm that can still be assigned. Falling back to the literal first would
      # make a retired variant the baseline, which reads as an empty control column.
      baseline = Enum.find(variants, &(&1.weight > 0)) || List.first(variants)
      Enum.map(variants, &%{&1 | control?: &1 == baseline})
    end
  end

  defp normalise_events(nil), do: nil
  defp normalise_events(list) when is_list(list), do: Enum.map(list, &to_string/1)

  defp maybe_string(nil), do: nil
  defp maybe_string(value), do: to_string(value)

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  @doc "`\"solving_emails\"` -> `\"Solving emails\"`, for anything the app did not label."
  def humanize(name) when is_binary(name) do
    name |> String.replace(["_", "-"], " ") |> String.capitalize()
  end
end
