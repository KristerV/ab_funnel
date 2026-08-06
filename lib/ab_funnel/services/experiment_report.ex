defmodule AbFunnel.Services.ExperimentReport do
  @moduledoc """
  One experiment's numbers: who was in it, how far they got, and whether the difference
  between the arms means anything.

  The order of the steps below is the point of the module. Gating comes before counting,
  because a funnel built from everyone holding a cookie is not a funnel — it counts people
  who never reached the thing under test, which is how a step ends up with more people in
  it than the step above it. Significance comes last, over the gated population only.
  """

  alias AbFunnel.Experiment
  alias AbFunnel.Services.Funnel
  alias AbFunnel.Services.Touches
  alias AbFunnel.Stats

  # Below this, a conversion rate is a rumour. Reported as-is, but never as a verdict.
  @minimum_arm 30

  def run(%Experiment{} = experiment, %{touches: touches, people: people}) do
    with {:ok, cohort} <- cohort(experiment, people),
         {:ok, journeys} <- journeys(experiment, cohort, touches),
         {:ok, cohort} <- entered(cohort, journeys),
         {:ok, funnels} <- funnels(experiment, cohort, journeys),
         {:ok, goal} <- goal(experiment, funnels),
         {:ok, arms} <- arms(experiment, cohort, journeys, goal),
         {:ok, required} <- required_per_arm(experiment, arms) do
      {:ok,
       %{
         key: experiment.key,
         label: experiment.label,
         entry: experiment.entry,
         goal: goal,
         declared_steps?: experiment.steps != nil,
         exposed: Enum.sum(Enum.map(arms, & &1.exposed)),
         arms: arms,
         funnels: funnels,
         required_per_arm: required,
         srm: srm(experiment, arms),
         verdict: verdict(arms, goal, required)
       }}
    end
  end

  # Everyone whose first event put them in this experiment. People who forced their own
  # bucket are already excluded by `Touches.variant_in/2`.
  defp cohort(experiment, people) do
    cohort =
      people
      |> Enum.flat_map(fn {person, attrs} ->
        case Touches.variant_in(attrs, experiment.key) do
          nil -> []
          variant -> [{person, %{variant: variant, source: attrs.source}}]
        end
      end)
      |> Map.new()

    {:ok, cohort}
  end

  @doc """
  Each person's events, trimmed to the journey the experiment is actually about.

  Two cuts, in this order:

    * `since` — everything before the experiment started. Restarting a test after a fix
      should not have to mean dropping the table.
    * `entry` — the event that puts someone *in* the funnel. Anyone who never fired it is
      dropped entirely, and everyone else loses whatever they did beforehand. That is what
      keeps a `signed_in` fired on the landing page out of a checkout funnel, and it makes
      a step above the entry count arithmetically impossible.

  Without an entry event both cuts are skipped and every person with any event counts,
  which is the old behaviour and still the default.
  """
  def journeys(experiment, cohort, touches) do
    journeys =
      touches
      |> Enum.filter(&Map.has_key?(cohort, &1.person))
      |> Enum.group_by(& &1.person)
      |> Enum.flat_map(fn {person, person_touches} ->
        person_touches
        |> after_since(experiment.since)
        |> after_entry(experiment.entry)
        |> case do
          [] -> []
          gated -> [{person, gated}]
        end
      end)
      |> Map.new()

    {:ok, journeys}
  end

  defp after_since(touches, nil), do: touches
  defp after_since(touches, %DateTime{} = since), do: from_moment(touches, since)

  defp after_entry(touches, nil), do: touches

  defp after_entry(touches, entry) do
    case Enum.find(touches, &(&1.event == entry)) do
      nil -> []
      %{at: at} -> from_moment(touches, at)
    end
  end

  # A step counts if the person reached it *at any point* after the cut — hence the last
  # touch, not the first. Someone who signs in on the landing page and again inside the
  # deck did sign in inside the deck, and dropping them because their first sign-in was
  # earlier would undercount the step.
  #
  # Its position, though, comes from the first touch, floored at the cut: the exact moment
  # of the first in-window occurrence is not recoverable from an aggregate, and the cut is
  # its lower bound. Only inferred ordering reads this, and a declared step list — which is
  # what an experiment with an entry event almost always has — ignores it entirely.
  defp from_moment(touches, moment) do
    touches
    |> Enum.filter(&(DateTime.compare(&1.last, moment) != :lt))
    |> Enum.map(fn touch ->
      if DateTime.compare(touch.at, moment) == :lt, do: %{touch | at: moment}, else: touch
    end)
  end

  defp entered(cohort, journeys), do: {:ok, Map.take(cohort, Map.keys(journeys))}

  defp funnels(experiment, cohort, journeys) do
    by_variant = Enum.group_by(Map.keys(cohort), &cohort[&1].variant)

    funnels =
      experiment.variants
      |> Enum.map(fn variant ->
        people = Map.get(by_variant, variant.key, [])
        {:ok, steps} = Funnel.run(experiment, variant.key, Map.take(journeys, people))

        %{
          variant: variant.key,
          label: variant.label,
          control?: variant.control?,
          people: length(people),
          steps: steps,
          sources: sources(experiment, variant, people, cohort, journeys)
        }
      end)
      # A retired arm nobody is in is noise; a live arm nobody is in is a broken
      # experiment, and has to stay visible.
      |> Enum.reject(&(&1.people == 0 and retired?(experiment, &1.variant)))

    {:ok, funnels}
  end

  defp retired?(experiment, variant_key) do
    Enum.any?(experiment.variants, &(&1.key == variant_key and &1.weight == 0))
  end

  # Only when there is more than one, because splitting a small experiment by traffic
  # source turns one thin funnel into several meaningless ones.
  defp sources(experiment, variant, people, cohort, journeys) do
    grouped = Enum.group_by(people, &cohort[&1].source)

    if map_size(grouped) < 2 do
      []
    else
      grouped
      |> Enum.map(fn {source, source_people} ->
        {:ok, steps} = Funnel.run(experiment, variant.key, Map.take(journeys, source_people))
        %{source: source, people: length(source_people), steps: steps}
      end)
      |> Enum.sort_by(&{-&1.people, &1.source})
    end
  end

  # The conversion every arm is judged on. Declared, or the last step of the control's
  # funnel — the end of the funnel is what a funnel is for.
  defp goal(%Experiment{goal: goal}, _funnels) when is_binary(goal), do: {:ok, goal}

  defp goal(_experiment, funnels) do
    control = Enum.find(funnels, & &1.control?) || List.first(funnels)

    {:ok, control && control.steps |> List.last() |> then(&(&1 && &1.event))}
  end

  defp arms(experiment, cohort, journeys, goal) do
    reached =
      journeys
      |> Enum.filter(fn {_person, touches} -> Enum.any?(touches, &(&1.event == goal)) end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    tally =
      Map.new(experiment.variants, fn variant ->
        people = for {person, %{variant: v}} <- cohort, v == variant.key, do: person

        {variant.key, {length(people), Enum.count(people, &MapSet.member?(reached, &1))}}
      end)

    control = Experiment.control(experiment)
    baseline = control && Map.get(tally, control.key)

    arms =
      Enum.map(experiment.variants, fn variant ->
        {exposed, converted} = Map.fetch!(tally, variant.key)

        %{
          variant: variant.key,
          label: variant.label,
          control?: variant.control?,
          exposed: exposed,
          converted: converted,
          rate: if(exposed > 0, do: converted / exposed),
          comparison: if(not variant.control?, do: Stats.compare(baseline, {exposed, converted}))
        }
      end)
      |> Enum.reject(&(&1.exposed == 0 and retired?(experiment, &1.variant)))

    {:ok, arms}
  end

  defp required_per_arm(experiment, arms) do
    control = Enum.find(arms, & &1.control?)

    required =
      if control && control.rate && control.rate > 0 do
        Stats.sample_size(control.rate, experiment.mde, length(arms))
      end

    {:ok, required}
  end

  defp srm(experiment, arms) do
    observed = Enum.map(arms, &{&1.variant, &1.exposed})

    weights =
      experiment.variants
      |> Enum.filter(&(&1.weight > 0))
      |> Enum.map(&{&1.key, &1.weight})

    observed = Enum.filter(observed, fn {key, _} -> List.keymember?(weights, key, 0) end)

    case Stats.srm(observed, weights) do
      nil -> %{checked?: false, p_value: nil, ok?: true}
      p -> %{checked?: true, p_value: p, ok?: p >= 0.001}
    end
  end

  @doc """
  What the numbers currently support saying out loud.

    * `:no_goal` — nothing to measure. The experiment has no goal event and no steps.
    * `:collecting` — an arm is still too small for a rate to mean anything.
    * `:leading` — one arm is ahead at p < 0.05, but the experiment has not reached the
      size it was designed for. This is the state a dashboard normally reports as a win,
      and it is the reason experiments "win" and then fail to replicate: watch a coin-flip
      long enough and it crosses 0.05 eventually. It is called out, not called.
    * `:winner` — ahead at p < 0.05 *and* past the sample size for the declared effect.
    * `:no_difference` — ran to size, found nothing. A real and useful result.
    * `:inconclusive` — past the minimum, under the target, nothing significant yet.
  """
  def verdict(arms, goal, required) do
    control = Enum.find(arms, & &1.control?)
    smallest = arms |> Enum.map(& &1.exposed) |> Enum.sort() |> List.first()
    leader = leader(arms, control)
    powered? = required != nil and smallest != nil and smallest >= required

    cond do
      goal == nil or control == nil or control.rate == nil ->
        %{state: :no_goal, leader: nil, progress: nil}

      smallest < @minimum_arm ->
        %{state: :collecting, leader: nil, progress: progress(smallest, required)}

      leader && powered? ->
        %{state: :winner, leader: leader, progress: 1.0}

      leader ->
        %{state: :leading, leader: leader, progress: progress(smallest, required)}

      powered? ->
        %{state: :no_difference, leader: nil, progress: 1.0}

      true ->
        %{state: :inconclusive, leader: nil, progress: progress(smallest, required)}
    end
  end

  # The best arm that is both ahead of the control and significantly so. "Ahead" is
  # checked separately from the p-value: a two-sided test is just as significant when the
  # challenger is losing, and reporting that as a leader would ship the worse variant.
  defp leader(_arms, nil), do: nil
  defp leader(_arms, %{rate: nil}), do: nil

  defp leader(arms, control) do
    arms
    |> Enum.reject(& &1.control?)
    |> Enum.filter(fn arm ->
      arm.comparison && arm.comparison.p_value < 0.05 && arm.rate > control.rate
    end)
    |> Enum.sort_by(& &1.rate, :desc)
    |> List.first()
  end

  defp progress(_smallest, nil), do: nil
  defp progress(_smallest, 0), do: nil
  defp progress(smallest, required), do: min(smallest / required, 1.0)
end
