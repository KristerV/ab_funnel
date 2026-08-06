defmodule AbFunnel.AssignmentTest do
  @moduledoc """
  Which arm a visitor lands in.

  Two properties carry the whole experiment: the same visitor must always get the same
  answer, and the visitor must not be able to choose it.
  """
  use ExUnit.Case, async: true

  alias AbFunnel.Assignment
  alias AbFunnel.Experiments

  defp deck, do: Experiments.fetch("deck")
  defp pricing, do: Experiments.fetch("pricing")
  defp ids(n), do: Enum.map(1..n, &"visitor-#{&1}")

  describe "bucketing" do
    test "the same visitor always gets the same arm" do
      for id <- ids(50) do
        assert Assignment.assign(deck(), id) == Assignment.assign(deck(), id)
      end
    end

    test "experiments are independent of each other" do
      # If they were not, being in `features` would predict your pricing arm and the two
      # tests would be measuring each other.
      pairs =
        for id <- ids(200) do
          {Assignment.assign(deck(), id), Assignment.assign(pricing(), id)}
        end

      assert pairs |> Enum.uniq() |> length() == 4
    end

    test "an even split comes out roughly even" do
      counts = ids(2000) |> Enum.map(&Assignment.assign(deck(), &1)) |> Enum.frequencies()

      assert_in_delta counts["features"] / 2000, 0.5, 0.05
    end

    test "weights are honoured" do
      counts = ids(2000) |> Enum.map(&Assignment.assign(pricing(), &1)) |> Enum.frequencies()

      assert_in_delta counts["annual"] / 2000, 0.1, 0.03
    end

    test "a retired variant is never handed out" do
      flow = Experiments.fetch("flow")

      refute "old" in Enum.map(ids(500), &Assignment.assign(flow, &1))
    end
  end

  describe "resolve/2" do
    test "assigns every running experiment for a visitor with nothing stored" do
      {assignments, state} = Assignment.resolve("visitor-1", %{})

      assert Map.keys(assignments) |> Enum.sort() == ["deck", "flow", "pricing"]
      assert state == :changed
    end

    test "leaves a stored assignment alone" do
      {stored, :changed} = Assignment.resolve("visitor-1", %{})
      {again, state} = Assignment.resolve("visitor-1", stored)

      assert again == stored
      assert state == :unchanged
    end

    test "keeps honouring a variant that has since been retired" do
      # Retiring an arm stops new assignments. Rerolling whoever already has it would put
      # their before and after in different buckets, which is worse than the retirement.
      {assignments, _} = Assignment.resolve("visitor-1", %{"flow" => "old"})

      assert assignments["flow"] == "old"
    end

    test "throws away a variant nobody declares and assigns a real one" do
      {assignments, state} = Assignment.resolve("visitor-1", %{"deck" => "i-picked-this"})

      assert assignments["deck"] in ["features", "solving_emails"]
      assert state == :changed
    end

    test "throws away an experiment nobody declares" do
      {assignments, _} = Assignment.resolve("visitor-1", %{"made_up" => "features"})

      refute Map.has_key?(assignments, "made_up")
    end

    test "an experiment with every arm retired has nothing to hand out" do
      # And so must not report a change — that would rewrite the cookie on every single
      # request, forever, without ever having anything to add to it.
      dead = Experiments.normalise(%{key: :dead, variants: [%{key: :old, active: false}]})

      assert Assignment.assign(dead, "visitor-1") == nil
    end

    test "only assigns the new experiment when one is added" do
      {full, _} = Assignment.resolve("visitor-1", %{})
      partial = Map.delete(full, "pricing")

      {assignments, state} = Assignment.resolve("visitor-1", partial)

      assert state == :changed
      assert Map.take(assignments, ["deck", "flow"]) == Map.take(full, ["deck", "flow"])
      assert assignments["pricing"] == full["pricing"]
    end
  end

  describe "the cookie" do
    test "round-trips" do
      assignments = %{"deck" => "features", "pricing" => "annual"}

      assert assignments |> Assignment.encode() |> Assignment.decode() == assignments
    end

    test "survives anything a client may have put there" do
      assert Assignment.decode(nil) == %{}
      assert Assignment.decode("") == %{}
      assert Assignment.decode("garbage") == %{}
      assert Assignment.decode("|:|::|") == %{}
      assert Assignment.decode("deck:features|junk") == %{"deck" => "features"}
    end

    test "validate/1 keeps only pairs the app actually declares" do
      assert Assignment.validate(%{
               "deck" => "features",
               "deck_typo" => "features",
               "pricing" => "made-up"
             }) == %{"deck" => "features"}
    end
  end

  describe "the QA marker" do
    test "identifies a visitor who chose their own bucket" do
      refute Assignment.qa?(%{"deck" => "features"})
      assert Assignment.qa?(%{"deck" => "features", Assignment.qa_key() => "1"})
    end
  end
end
