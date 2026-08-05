defmodule AbFunnel.Services.ReportTest do
  @moduledoc """
  The funnel math, and specifically what happens when one human shows up as several
  browsers — which is the normal case the moment a funnel spans a magic-link login.

  Counts are people. A person who runs the same flow on a phone and then again on a
  laptop must read as one person who reached each step, not as two.
  """
  use ExUnit.Case, async: true

  alias AbFunnel.Services.Report

  @steps ~w(landing generate_submitted generated signup_requested registered generated_as_user)

  # Explicit timestamps rather than insertion order: step order is derived from when
  # each person reached each step, so the test has to control that directly.
  defp event(visitor_id, event, minute, opts \\ []) do
    %AbFunnel.Resources.Event{
      visitor_id: visitor_id,
      event: event,
      variant: Keyword.get(opts, :variant, "control"),
      metadata: %{},
      inserted_at: DateTime.add(~U[2026-08-01 12:00:00.000000Z], minute, :minute)
    }
  end

  defp steps_for(funnel, variant \\ "control", source \\ "direct") do
    {^variant, sources} = List.keyfind(funnel, variant, 0)
    {^source, steps} = List.keyfind(sources, source, 0)
    steps
  end

  describe "one person, one browser" do
    test "counts each step once and orders them by when they were reached" do
      events = @steps |> Enum.with_index() |> Enum.map(fn {e, i} -> event("v1", e, i) end)

      assert steps_for(Report.funnel(events, %{})) ==
               Enum.map(@steps, &{&1, 1})
    end

    test "generating three codes still counts as one person at that step" do
      events = [
        event("v1", "landing", 0),
        event("v1", "generated", 1),
        event("v1", "generated", 2),
        event("v1", "generated", 3)
      ]

      assert steps_for(Report.funnel(events, %{})) == [{"landing", 1}, {"generated", 1}]
    end
  end

  describe "one person, two browsers" do
    # The phone runs the anonymous flow and asks for a magic link. Days later the laptop
    # arrives fresh, lands, logs in and makes a code. Seven events, six steps, one human
    # — and the laptop repeats only *part* of what the phone did, which is what makes
    # the step positions interesting.
    setup do
      phone = [
        event("phone", "landing", 0),
        event("phone", "generate_submitted", 1),
        event("phone", "generated", 2),
        event("phone", "signup_requested", 3)
      ]

      laptop = [
        event("laptop", "landing", 10),
        event("laptop", "registered", 11),
        event("laptop", "generated_as_user", 12)
      ]

      %{
        events: phone ++ laptop,
        aliases: %{"phone" => "person-a", "laptop" => "person-a"}
      }
    end

    test "reads as a single person completing every step", %{events: events, aliases: aliases} do
      assert steps_for(Report.funnel(events, aliases)) == Enum.map(@steps, &{&1, 1})
    end

    test "without the binding the same data double-counts the top of the funnel", %{
      events: events
    } do
      steps = Map.new(steps_for(Report.funnel(events, %{})))

      # Two browsers both landed, so step 1 reads 2 while the tail reads 1 — the shape
      # that makes a conversion rate impossible to read.
      assert steps["landing"] == 2
      assert steps["registered"] == 1
    end

    test "keeps the steps in the right order despite the repeated landing", %{
      events: events,
      aliases: aliases
    } do
      # Ordering is by average position within a person's journey. Counting every
      # occurrence, the laptop's second `landing` sits at index 4 and drags that step's
      # average to 2.0 — behind `generate_submitted` at 1.0, which never repeated. Only
      # by collapsing to each person's *first* arrival at a step does `landing` stay
      # first.
      assert steps_for(Report.funnel(events, aliases)) |> Enum.map(&elem(&1, 0)) == @steps

      assert Report.step_order(Report.resolve_people(events, aliases))
             |> Enum.sort_by(&elem(&1, 1))
             |> Enum.map(&elem(&1, 0)) == @steps
    end
  end

  describe "identify at any point" do
    test "binds retroactively — events written before the binding still resolve" do
      events = [
        event("phone", "landing", 0),
        event("phone", "generated", 1),
        event("laptop", "registered", 2)
      ]

      unbound = Map.new(steps_for(Report.funnel(events, %{})))
      bound = Map.new(steps_for(Report.funnel(events, %{"phone" => "p", "laptop" => "p"})))

      assert unbound["landing"] == 1 and unbound["registered"] == 1
      assert bound["landing"] == 1 and bound["registered"] == 1

      assert Report.resolve_people(events, %{"phone" => "p", "laptop" => "p"})
             |> Enum.map(& &1.visitor_id)
             |> Enum.uniq() == ["p"]
    end

    test "leaves unidentified visitors as their own person" do
      events = [event("anon", "landing", 0), event("phone", "landing", 0)]

      assert Report.resolve_people(events, %{"phone" => "person-a"})
             |> Enum.map(& &1.visitor_id) == ["anon", "person-a"]
    end
  end

  describe "source attribution" do
    test "first touch wins when a person arrives from two places" do
      events = [
        event("phone", "source:google", 0),
        event("phone", "landing", 1),
        event("laptop", "source:twitter", 10),
        event("laptop", "registered", 11)
      ]

      funnel = Report.funnel(events, %{"phone" => "person-a", "laptop" => "person-a"})

      assert steps_for(funnel, "control", "google") == [{"landing", 1}, {"registered", 1}]
      assert List.keyfind(funnel, "control", 0) |> elem(1) |> length() == 1
    end

    test "source events never appear as funnel steps" do
      events = [event("v1", "source:google", 0), event("v1", "landing", 1)]

      assert steps_for(Report.funnel(events, %{}), "control", "google") == [{"landing", 1}]
    end
  end

  describe "variants" do
    test "each variant gets its own funnel" do
      events = [
        event("v1", "landing", 0, variant: "control"),
        event("v2", "landing", 0, variant: "treatment"),
        event("v2", "generated", 1, variant: "treatment")
      ]

      funnel = Report.funnel(events, %{})

      assert steps_for(funnel, "control") == [{"landing", 1}]
      assert steps_for(funnel, "treatment") == [{"landing", 1}, {"generated", 1}]
    end
  end

  describe "one person assigned to two variants" do
    # Variant assignment is a cookie, so it is rolled once per browser. A person on two
    # devices gets two independent rolls and lands in different buckets about half the
    # time — the most damaging thing that can happen to an A/B comparison, because it
    # splits real journeys across the two arms being compared.
    setup do
      %{
        events: [
          event("phone", "landing", 0, variant: "control"),
          event("phone", "generated", 1, variant: "control"),
          event("laptop", "registered", 2, variant: "treatment"),
          event("laptop", "generated_as_user", 3, variant: "treatment")
        ],
        aliases: %{"phone" => "person-a", "laptop" => "person-a"}
      }
    end

    test "the whole journey lands in the variant they were assigned first", %{
      events: events,
      aliases: aliases
    } do
      funnel = Report.funnel(events, aliases)

      assert Enum.map(funnel, &elem(&1, 0)) == ["control"]

      assert steps_for(funnel, "control") == [
               {"landing", 1},
               {"generated", 1},
               {"registered", 1},
               {"generated_as_user", 1}
             ]
    end

    test "the later variant contributes no separate arm at all", %{
      events: events,
      aliases: aliases
    } do
      # Not merely "mostly control": `treatment` must not appear as a second arm holding
      # the tail of their journey, because that is what makes the two arms look different
      # when the only difference is which device someone finished on.
      funnel = Report.funnel(events, aliases)

      refute List.keyfind(funnel, "treatment", 0)
    end

    test "genuinely separate people keep their own variants", %{events: events} do
      # The fix must not over-merge: with no binding these are two people, two arms.
      funnel = Report.funnel(events, %{})

      assert Enum.map(funnel, &elem(&1, 0)) == ["control", "treatment"]
    end
  end

  describe "ordering by real timestamps" do
    test "steps seconds apart stay in order" do
      # Comparing `DateTime` structs with the default sorter falls back to Erlang term
      # order, which ranks the struct's fields alphabetically — putting `microsecond`
      # ahead of `minute` and `second`. Timestamps that differ below the minute, which
      # is every real session, then sort essentially at random.
      events = [
        %AbFunnel.Resources.Event{
          visitor_id: "v1",
          event: "landing",
          variant: "control",
          inserted_at: ~U[2026-08-01 12:00:01.900000Z]
        },
        %AbFunnel.Resources.Event{
          visitor_id: "v1",
          event: "generated",
          variant: "control",
          inserted_at: ~U[2026-08-01 12:00:09.100000Z]
        },
        %AbFunnel.Resources.Event{
          visitor_id: "v1",
          event: "registered",
          variant: "control",
          inserted_at: ~U[2026-08-01 12:01:00.050000Z]
        }
      ]

      assert steps_for(Report.funnel(events, %{})) |> Enum.map(&elem(&1, 0)) ==
               ["landing", "generated", "registered"]
    end
  end

  test "no events is an empty funnel, not a crash" do
    assert Report.funnel([], %{}) == []
  end
end
