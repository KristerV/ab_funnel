defmodule AbFunnel.ExperimentsTest do
  @moduledoc """
  Turning a loose declaration into something the rest of the library can rely on.

  Every default here exists so that an app can declare the minimum and still get sensible
  behaviour — and so that the fields it *does* declare are never silently ignored.
  """
  use ExUnit.Case, async: true

  alias AbFunnel.Experiment
  alias AbFunnel.Experiments

  defp normalise(attrs), do: Experiments.normalise(attrs)

  describe "variants" do
    test "a bare list of names is enough" do
      experiment = normalise(%{key: :flow, variants: [:control, :treatment]})

      assert Enum.map(experiment.variants, & &1.key) == ["control", "treatment"]
      assert Enum.map(experiment.variants, & &1.weight) == [1, 1]
    end

    test "a keyword list carries the weights" do
      experiment = normalise(%{key: :pricing, variants: [monthly: 90, annual: 10]})

      assert Enum.map(experiment.variants, & &1.weight) == [90, 10]
    end

    test "labels default to something readable" do
      experiment = normalise(%{key: :deck, variants: [:solving_emails]})

      assert Experiment.variant_label(experiment, "solving_emails") == "Solving emails"
      assert experiment.label == "Deck"
    end

    test "the first assignable variant is the control unless one says otherwise" do
      first = normalise(%{key: :a, variants: [:control, :treatment]})
      declared = normalise(%{key: :b, variants: [:one, %{key: :two, control: true}]})

      assert Experiment.control(first).key == "control"
      assert Experiment.control(declared).key == "two"
    end

    test "a retired variant is never the control" do
      # It would read as an empty baseline column, and every comparison against it would
      # be against nothing.
      experiment =
        normalise(%{key: :a, variants: [%{key: :old, active: false}, %{key: :new}]})

      assert Experiment.control(experiment).key == "new"
    end

    test "`active: false` means keep honouring it, stop handing it out" do
      experiment = normalise(%{key: :a, variants: [:new, %{key: :old, active: false}]})

      assert Experiment.known?(experiment, "old")
      assert Enum.map(Experiment.assignable(experiment), & &1.key) == ["new"]
    end
  end

  describe "steps" do
    test "a plain list applies to every variant" do
      experiment = normalise(%{key: :a, variants: [:x, :y], steps: [:one, :two]})

      assert Experiments.steps_for(experiment, "x") == ["one", "two"]
      assert Experiments.steps_for(experiment, "y") == ["one", "two"]
    end

    test "an MFA is resolved per variant" do
      experiment =
        normalise(%{key: :a, variants: [:x, :y], steps: {__MODULE__, :steps_for_variant, 1}})

      assert Experiments.steps_for(experiment, "x") == ["x_start", "done"]
      assert Experiments.steps_for(experiment, "y") == ["y_start", "done"]
    end

    def steps_for_variant(variant), do: ["#{variant}_start", "done"]

    test "entry and goal default to the ends of the control's funnel" do
      experiment = normalise(%{key: :a, variants: [:x], steps: ~w(started middle finished)})

      assert experiment.entry == "started"
      assert experiment.goal == "finished"
    end

    test "declaring either one wins over the default" do
      experiment =
        normalise(%{
          key: :a,
          variants: [:x],
          steps: ~w(started middle finished),
          entry: "middle",
          goal: "middle"
        })

      assert experiment.entry == "middle"
      assert experiment.goal == "middle"
    end

    test "with no steps there is nothing to infer an entry from" do
      experiment = normalise(%{key: :a, variants: [:x]})

      assert experiment.entry == nil
      assert experiment.goal == nil
      assert Experiments.steps_for(experiment, "x") == nil
    end
  end

  describe "the module as configured" do
    test "reads the test declarations" do
      assert Enum.map(Experiments.all(), & &1.key) == ["deck", "flow", "pricing"]
    end

    test "owning/1 attributes a bare variant name to the experiment that declares it" do
      # How events and cookies written before experiments existed are read.
      assert Experiments.owning("features").key == "deck"
      assert Experiments.owning("monthly").key == "pricing"
      assert Experiments.owning("nonsense") == nil
    end

    test "fetch/1 takes a string or an atom" do
      assert Experiments.fetch("deck").key == "deck"
      assert Experiments.fetch(:deck).key == "deck"
      assert Experiments.fetch(:missing) == nil
    end
  end
end
