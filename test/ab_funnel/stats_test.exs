defmodule AbFunnel.StatsTest do
  @moduledoc """
  The maths, checked against values you can look up.

  The point of this module is to stop a dashboard reporting a coin flip as a result, so
  the tests that matter most are the ones asserting it does *not* find significance.
  """
  use ExUnit.Case, async: true

  alias AbFunnel.Stats

  defp close(a, b, tolerance \\ 0.001), do: abs(a - b) <= tolerance

  describe "normal_cdf/1" do
    test "matches the table" do
      assert close(Stats.normal_cdf(0.0), 0.5)
      assert close(Stats.normal_cdf(1.0), 0.8413)
      assert close(Stats.normal_cdf(1.96), 0.9750)
      assert close(Stats.normal_cdf(-1.96), 0.0250)
      assert close(Stats.normal_cdf(2.576), 0.9950)
    end
  end

  describe "compare/2" do
    test "finds nothing in a difference this small" do
      # 30 of 300 against 33 of 300. Ten percent better, and completely unremarkable.
      %{p_value: p} = Stats.compare({300, 30}, {300, 33})

      assert p > 0.05
    end

    test "finds a large difference on a large sample" do
      # 100 of 1000 against 150 of 1000 — a 50% lift, which at this size is real.
      %{p_value: p, uplift: uplift} = Stats.compare({1000, 100}, {1000, 150})

      assert p < 0.001
      assert close(uplift, 0.5)
    end

    test "does not mistake four people for a result" do
      # The shape of every premature call: 1 of 4 against 3 of 4, a 200% lift.
      %{p_value: p} = Stats.compare({4, 1}, {4, 3})

      assert p > 0.05
    end

    test "the confidence interval straddles zero exactly when the result does not hold" do
      %{confidence_interval: {low, high}} = Stats.compare({300, 30}, {300, 33})
      assert low < 0 and high > 0

      %{confidence_interval: {low, high}} = Stats.compare({1000, 100}, {1000, 150})
      assert low > 0 and high > 0
    end

    test "is nil rather than a division by zero when an arm is empty" do
      assert Stats.compare({0, 0}, {100, 10}) == nil
      assert Stats.compare({100, 10}, {0, 0}) == nil
    end

    test "identical arms are as insignificant as it gets" do
      assert close(Stats.compare({500, 50}, {500, 50}).p_value, 1.0)
    end
  end

  describe "sample_size/3" do
    test "a 20% lift on a 10% baseline needs a few thousand per arm" do
      # The number worth internalising: a small effect on a small baseline is expensive,
      # and this is why most experiments are called far too early.
      n = Stats.sample_size(0.10, 0.20)

      assert n > 3_000 and n < 4_500
    end

    test "a bigger effect is cheaper to detect" do
      assert Stats.sample_size(0.10, 0.50) < Stats.sample_size(0.10, 0.20)
    end

    test "more arms cost more" do
      assert Stats.sample_size(0.10, 0.20, 3) > Stats.sample_size(0.10, 0.20, 2)
    end

    test "is nil where there is nothing to size" do
      assert Stats.sample_size(0.0, 0.2) == nil
      assert Stats.sample_size(1.0, 0.2) == nil
      assert Stats.sample_size(0.1, 0.0) == nil
    end
  end

  describe "srm/2" do
    test "a clean 50/50 split raises nothing" do
      assert Stats.srm([{"a", 5000}, {"b", 4950}], [{"a", 50}, {"b", 50}]) > 0.001
    end

    test "a badly broken split is caught" do
      # 40/60 where 50/50 was intended. Something is routing traffic, and no conversion
      # analysis on top of it is worth reading.
      assert Stats.srm([{"a", 4000}, {"b", 6000}], [{"a", 50}, {"b", 50}]) < 0.001
    end

    test "an intentionally uneven split is not a mismatch" do
      assert Stats.srm([{"a", 9000}, {"b", 1000}], [{"a", 90}, {"b", 10}]) > 0.001
    end

    test "stays quiet when there is too little data to say" do
      assert Stats.srm([{"a", 6}, {"b", 14}], [{"a", 50}, {"b", 50}]) == nil
      assert Stats.srm([{"a", 100}], [{"a", 100}]) == nil
    end
  end
end
