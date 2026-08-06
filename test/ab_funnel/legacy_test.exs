defmodule AbFunnel.LegacyTest do
  @moduledoc """
  An app that installed AbFunnel before experiments existed.

  It has a module doing `use AbFunnel.Variants`, config pointing at `:variants`, a table of
  events with a `variant` column and no assignments, and browsers holding an
  `ab_funnel_variant` cookie. None of that may break, and none of it may need editing —
  upgrading the library has to be a `mix deps.update` and nothing else.
  """
  use AbFunnel.DataCase, async: false

  import Plug.Test

  alias AbFunnel.Experiments
  alias AbFunnel.Resources.Event

  setup do
    put_experiments(nil)
    :ok
  end

  defp legacy_event(visitor_id, event, minute, variant) do
    AbFunnel.TestRepo.insert!(%Event{
      visitor_id: visitor_id,
      event: event,
      variant: variant,
      assignments: %{},
      inserted_at: at(minute),
      updated_at: at(minute)
    })
  end

  describe "the variants module" do
    test "answers as a single unnamed experiment" do
      assert [experiment] = Experiments.all()

      assert experiment.key == "default"
      assert Enum.map(experiment.variants, & &1.key) == ["control", "treatment", "old"]
    end

    test "keeps the behaviour it had: inferred order, no entry event, everyone counted" do
      assert [experiment] = Experiments.all()

      assert experiment.entry == nil
      assert experiment.steps == nil
    end

    test "a retired variant stays known but stops being assigned" do
      assert [experiment] = Experiments.all()

      assert AbFunnel.Experiment.known?(experiment, "old")

      assert Enum.map(AbFunnel.Experiment.assignable(experiment), & &1.key) ==
               ["control", "treatment"]
    end

    test "still answers the old API directly" do
      assert length(AbFunnel.TestVariants.all()) == 3
      assert AbFunnel.TestVariants.keys() == [:control, :treatment]
      assert AbFunnel.TestVariants.name(:control) == "Control"
      assert AbFunnel.TestVariants.name("control") == "Control"
      assert AbFunnel.TestVariants.name("unknown_thing") == "unknown_thing"
      assert AbFunnel.TestVariants.random_key() in [:control, :treatment]
      assert AbFunnel.TestVariants.known?("old")
    end

    test "no active variants fails with a message that says what to do" do
      assert_raise RuntimeError, ~r/no active variants/, fn ->
        AbFunnel.InactiveVariants.random_key()
      end
    end
  end

  describe "events written before experiments existed" do
    test "still report, under the experiment that declares their variant" do
      legacy_event("a", "landing", 0, "control")
      legacy_event("a", "generated", 1, "control")
      legacy_event("b", "landing", 0, "treatment")

      report = report()

      assert steps(report, "default", "control") == [{"landing", 1}, {"generated", 1}]
      assert arm(report, "default", "treatment").exposed == 1
    end

    test "mix with new ones for the same person without splitting them in two" do
      legacy_event("a", "landing", 0, "control")
      record("a", "generated", 1, %{"default" => "control"})

      assert steps(report(), "default", "control") == [{"landing", 1}, {"generated", 1}]
    end
  end

  describe "browsers holding the old cookie" do
    test "are not rerolled when the library is upgraded" do
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("ab_funnel_variant", "treatment")
        |> init_test_session(%{})
        |> AbFunnel.Plug.Visitor.call([])

      assert conn.assigns.ab_funnel_assignments == %{"default" => "treatment"}
      assert conn.assigns.ab_funnel_variant == "treatment"
    end

    test "a retired variant is still honoured for whoever already has it" do
      # Turning a variant off stops new assignments; it must not silently reroll people
      # mid-experiment, which would put their before and after in different buckets.
      conn =
        :get
        |> conn("/")
        |> put_req_cookie("ab_funnel_variant", "old")
        |> init_test_session(%{})
        |> AbFunnel.Plug.Visitor.call([])

      assert conn.assigns.ab_funnel_variant == "old"
    end
  end
end
