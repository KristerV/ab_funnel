defmodule AbFunnel.Services.LifecycleTest do
  @moduledoc """
  Experiments that are not simply running: one restarted after a fix, one switched off.

  Both exist so that the answer to "this test was broken for the first week" is never
  "drop the events table", which takes the working weeks with it.
  """
  use AbFunnel.DataCase, async: false

  setup do
    put_experiments(AbFunnel.LifecycleExperiments)
    :ok
  end

  @a %{"restarted" => "a"}
  @finished %{"finished" => "a"}

  describe "since" do
    test "ignores everything before the experiment restarted" do
      journey("early", ~w(landed done), @a)
      journey("late", ~w(landed done), @a, 10)

      assert arm(report(), "restarted", "a").exposed == 1
    end

    test "trims a person's own pre-restart events rather than dropping the person" do
      # They were mid-journey when the test restarted. What they did afterwards is still
      # valid data; what they did before is from a different experiment.
      record("a", "landed", 0, @a)
      record("a", "done", 10, @a)

      steps = report() |> steps("restarted", "a") |> Map.new()

      refute Map.has_key?(steps, "landed")
      assert steps["done"] == 1
    end

    test "keeps a step repeated on both sides of the restart" do
      record("a", "landed", 0, @a)
      record("a", "landed", 10, @a)

      assert report() |> steps("restarted", "a") == [{"landed", 1}]
    end
  end

  describe "active: false" do
    test "leaves the experiment out of the report" do
      journey("a", ~w(landed done), @finished)

      assert experiment(report(), "finished") == nil
    end

    test "include_inactive brings it back to read the result" do
      journey("a", ~w(landed done), @finished)

      assert arm(report(include_inactive: true), "finished", "a").exposed == 1
    end

    test "stops assigning new visitors to it" do
      {assignments, _} = AbFunnel.Assignment.resolve("visitor-1", %{})

      assert Map.keys(assignments) == ["restarted"]
    end
  end

  describe "window_days" do
    test "bounds how far back the report reads" do
      journey("a", ~w(landed done), @a, 10)

      # The events are dated well over a day ago, so a one-day window sees none of them.
      {:ok, report} = AbFunnel.Services.Report.run(window_days: 1)

      assert Enum.all?(report.experiments, &(&1.exposed == 0))
    end
  end
end
