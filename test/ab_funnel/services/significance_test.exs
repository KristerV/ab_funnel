defmodule AbFunnel.Services.SignificanceTest do
  @moduledoc """
  Whether the dashboard is allowed to call a result.

  The failure this guards against is not a wrong number, it is a right number presented
  too early: watch any two arms long enough and one of them crosses p < 0.05 by chance.
  So the interesting assertions here are the ones where a real, significant difference is
  deliberately *not* called a winner yet.
  """
  use AbFunnel.DataCase, async: false

  alias AbFunnel.Resources.Event
  alias AbFunnel.Services.ExperimentReport

  setup do
    put_experiments(AbFunnel.SignificanceExperiments)
    :ok
  end

  # Written in bulk: the verdicts only mean anything at a few hundred people per arm, and
  # a test that inserts them one at a time is a test nobody runs.
  defp cohort(prefix, assignments, count, converted, events) do
    rows =
      Enum.flat_map(1..count, fn i ->
        journey = if i <= converted, do: events, else: [List.first(events)]

        Enum.with_index(journey, fn event, minute ->
          %{
            visitor_id: "#{prefix}-#{i}",
            event: event,
            assignments: assignments,
            metadata: %{},
            inserted_at: at(minute),
            updated_at: at(minute)
          }
        end)
      end)

    AbFunnel.TestRepo.insert_all(Event, rows)
  end

  defp signup(variant, count, converted) do
    cohort("#{variant}", %{"signup" => variant}, count, converted, [
      "signup_started",
      "signup_done"
    ])
  end

  defp verdict, do: report() |> experiment("signup") |> Map.fetch!(:verdict)

  describe "the verdict" do
    test "says nothing at all while the arms are tiny" do
      signup("a", 20, 2)
      signup("b", 20, 12)

      # A sixfold difference, and still not something to act on.
      assert verdict().state == :collecting
    end

    test "reports a significant lead without calling it, under the target size" do
      signup("a", 100, 10)
      signup("b", 100, 25)

      %{state: state, leader: leader} = verdict()

      assert state == :leading
      assert leader.variant == "b"
    end

    test "calls a winner once the experiment is both significant and big enough" do
      signup("a", 200, 20)
      signup("b", 200, 40)

      %{state: state, leader: leader, progress: progress} = verdict()

      assert state == :winner
      assert leader.variant == "b"
      assert progress == 1.0
    end

    test "ran to size and found nothing is its own answer" do
      signup("a", 200, 20)
      signup("b", 200, 22)

      assert verdict().state == :no_difference
    end

    test "never names a losing arm as the leader" do
      # A two-sided test is just as significant when the challenger is worse, and reading
      # only the p-value would ship the losing variant.
      signup("a", 200, 40)
      signup("b", 200, 20)

      assert verdict().state == :no_difference
    end
  end

  describe "the arms table" do
    test "carries the rate, the lift and the confidence" do
      signup("a", 200, 20)
      signup("b", 200, 40)

      control = arm(report(), "signup", "a")
      challenger = arm(report(), "signup", "b")

      assert control.control?
      assert control.exposed == 200 and control.converted == 20
      assert_in_delta control.rate, 0.1, 0.001
      assert control.comparison == nil

      assert_in_delta challenger.comparison.uplift, 1.0, 0.001
      assert challenger.comparison.p_value < 0.05
    end

    test "sizes the experiment from the control's own rate" do
      signup("a", 200, 20)
      signup("b", 200, 40)

      # 10% baseline, "tell me about a doubling" — a couple of hundred per arm.
      assert experiment(report(), "signup").required_per_arm in 150..250
    end
  end

  describe "sample ratio mismatch" do
    test "an even split of a 90/10 experiment is caught" do
      cohort("h", %{"split" => "heavy"}, 500, 100, ["landed", "converted"])
      cohort("l", %{"split" => "light"}, 500, 100, ["landed", "converted"])

      srm = experiment(report(), "split").srm

      assert srm.checked?
      refute srm.ok?
    end

    test "a split that matches its weights raises nothing" do
      cohort("h", %{"split" => "heavy"}, 900, 90, ["landed", "converted"])
      cohort("l", %{"split" => "light"}, 100, 10, ["landed", "converted"])

      assert experiment(report(), "split").srm.ok?
    end

    test "is not checked at all while the numbers are small" do
      cohort("h", %{"split" => "heavy"}, 20, 2, ["landed", "converted"])
      cohort("l", %{"split" => "light"}, 20, 2, ["landed", "converted"])

      refute experiment(report(), "split").srm.checked?
    end
  end

  describe "more than two arms" do
    defp three(variant, count, converted) do
      cohort(variant, %{"three" => variant}, count, converted, ["landed", "converted"])
    end

    test "every challenger is measured against the control, not against each other" do
      three("a", 300, 30)
      three("b", 300, 45)
      three("c", 300, 75)

      assert arm(report(), "three", "a").comparison == nil
      assert_in_delta arm(report(), "three", "b").comparison.uplift, 0.5, 0.001
      assert_in_delta arm(report(), "three", "c").comparison.uplift, 1.5, 0.001
    end

    test "the best significant challenger is the leader, not merely the first" do
      three("a", 300, 30)
      three("b", 300, 60)
      three("c", 300, 90)

      assert experiment(report(), "three").verdict.leader.variant == "c"
    end

    test "a third arm costs more people, because there is another comparison to hold" do
      three("a", 300, 30)
      three("b", 300, 30)
      three("c", 300, 30)

      two_arm = AbFunnel.Stats.sample_size(0.1, 1.0, 2)

      assert experiment(report(), "three").required_per_arm > two_arm
    end

    test "a three-way split that has gone wrong is still caught" do
      # Two degrees of freedom rather than one — a different branch of the chi-square.
      three("a", 500, 50)
      three("b", 500, 50)
      three("c", 200, 20)

      refute experiment(report(), "three").srm.ok?
    end

    test "an even three-way split raises nothing" do
      three("a", 400, 40)
      three("b", 410, 41)
      three("c", 395, 40)

      assert experiment(report(), "three").srm.ok?
    end
  end

  describe "the dashboard" do
    test "says who won, and shows the mismatch alarm above everything when there is one" do
      # The render paths that only exist once an experiment has enough data: the leader's
      # name interpolated into the verdict, the progress bar, and the SRM banner.
      signup("a", 200, 20)
      signup("b", 200, 40)
      cohort("h", %{"split" => "heavy"}, 500, 100, ["landed", "converted"])
      cohort("l", %{"split" => "light"}, 500, 100, ["landed", "converted"])

      page =
        %{report: report(), __changed__: nil}
        |> AbFunnel.AdminLive.render()
        |> Phoenix.LiveViewTest.rendered_to_string()

      assert page =~ "B wins"
      assert page =~ "+100.0%"
      assert page =~ "Sample ratio mismatch"
    end
  end

  describe "verdict/3 on its own" do
    test "an experiment with no goal event says so rather than reporting zeroes" do
      arms = [%{control?: true, rate: nil, exposed: 0, comparison: nil, variant: "a"}]

      assert ExperimentReport.verdict(arms, nil, nil).state == :no_goal
    end
  end
end
