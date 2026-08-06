defmodule AbFunnel.Services.ReportTest do
  @moduledoc """
  The funnel math.

  Three things go wrong in an A/B funnel, and every test here is one of them:

    * **Who is in it.** Everyone holding a cookie is not the funnel — that is how a step
      ends up with more people than the step above it. Only people who fired the entry
      event count, and only what they did after firing it.
    * **What order the steps go in.** Declared beats inferred, and a step nobody reached
      has to render as `0` rather than vanish, because the drop-off is the whole point.
    * **Who counts as one person.** One human on a phone and a laptop is two browsers, and
      counting them twice at the top and once at the bottom makes every rate meaningless.
  """
  use AbFunnel.DataCase, async: true

  @features %{"deck" => "features"}
  @emails %{"deck" => "solving_emails"}
  @control %{"flow" => "control"}
  @treatment %{"flow" => "treatment"}

  @deck_steps ~w(deck_started slide_f_intro slide_cta deck_completed lead_submitted)

  defp event(visitor_id, name, at) do
    %AbFunnel.Resources.Event{
      visitor_id: visitor_id,
      event: name,
      assignments: %{"flow" => "control"},
      inserted_at: at,
      updated_at: at
    }
  end

  defp sources_of(report, experiment_key) do
    report
    |> experiment(experiment_key)
    |> Map.fetch!(:funnels)
    |> List.first()
    |> Map.fetch!(:sources)
  end

  describe "the entry event decides who is in the funnel" do
    test "someone who never fired it is not counted at all" do
      # The prod bug this was written for: three people signed in on the landing page and
      # never opened the deck, one person ran the whole deck. The dashboard read
      # "Deck started 1 -> Signed in 3", a 300% step conversion, on data where three of
      # the four had not entered the funnel.
      journey("runner", ~w(deck_started slide_f_intro slide_cta), @features)
      record("lurker-1", "signed_in", 0, @features)
      record("lurker-2", "signed_in", 0, @features)
      record("lurker-3", "signed_in", 0, @features)

      assert arm(report(), "deck", "features").exposed == 1
    end

    test "no step can be larger than the entry, whatever else people did" do
      journey("runner", ~w(deck_started slide_f_intro), @features)
      for i <- 1..5, do: record("lurker-#{i}", "signed_in", 0, @features)

      counts = report() |> steps("deck", "features") |> Enum.map(&elem(&1, 1))

      assert Enum.max(counts) == List.first(counts)
    end

    test "events fired before entering are trimmed away" do
      record("a", "signed_in", 0, @features)
      record("a", "deck_started", 5, @features)
      record("a", "slide_f_intro", 6, @features)

      steps = report() |> steps("deck", "features") |> Map.new()

      refute Map.has_key?(steps, "signed_in")
      assert steps["deck_started"] == 1
    end

    test "but a step done both before and after entering still counts" do
      # First-touch-wins is the right rule for ordering and the wrong one for membership:
      # they did click the CTA inside the deck, and their earlier click must not erase it.
      record("a", "slide_cta", 0, @features)
      record("a", "deck_started", 5, @features)
      record("a", "slide_cta", 6, @features)

      assert report() |> steps("deck", "features") |> Map.new() |> Map.get("slide_cta") == 1
    end

    test "an experiment with no entry event counts everyone, as it always did" do
      record("a", "landing", 0, @control)
      record("b", "landing", 0, @control)

      assert arm(report(), "flow", "control").exposed == 2
    end
  end

  describe "declared steps" do
    test "keep their order however the data falls" do
      journey("a", ~w(lead_submitted deck_started slide_f_intro), @features)

      assert report() |> steps("deck", "features") |> Enum.map(&elem(&1, 0)) == @deck_steps
    end

    test "render as zero when nobody reached them" do
      # The one thing the chart exists for. Inference drops a step nobody reached, which
      # hides the drop-off entirely.
      journey("a", ~w(deck_started slide_f_intro), @features)

      assert report() |> steps("deck", "features") == [
               {"deck_started", 1},
               {"slide_f_intro", 1},
               {"slide_cta", 0},
               {"deck_completed", 0},
               {"lead_submitted", 0}
             ]
    end

    test "exclude events that are not part of this funnel" do
      journey("a", ~w(deck_started slide_f_intro), @features)
      record("a", "signed_in", 10, @features)

      refute report() |> steps("deck", "features") |> Map.new() |> Map.has_key?("signed_in")
    end

    test "are resolved per variant, so two arms can be two different journeys" do
      journey("a", ~w(deck_started slide_f_intro), @features)
      journey("b", ~w(deck_started slide_s_intro), @emails)

      assert report() |> steps("deck", "features") |> Enum.map(&elem(&1, 0)) == @deck_steps

      assert report() |> steps("deck", "solving_emails") |> Enum.map(&elem(&1, 0)) ==
               ~w(deck_started slide_s_intro slide_cta deck_completed lead_submitted)
    end
  end

  describe "inferred steps, for an experiment that declares none" do
    test "are ordered by when people first reach them" do
      journey("a", ~w(landing generated registered), @control)

      assert report() |> steps("flow", "control") == [
               {"landing", 1},
               {"generated", 1},
               {"registered", 1}
             ]
    end

    test "collapse repeats, so a second visit does not drag a step rightward" do
      # Counting every occurrence, the second `landing` sits late in the list and drags
      # that step's average behind `generated`, reordering the chart.
      record("a", "landing", 0, @control)
      record("a", "generated", 1, @control)
      record("a", "landing", 2, @control)
      record("a", "registered", 3, @control)

      assert report() |> steps("flow", "control") == [
               {"landing", 1},
               {"generated", 1},
               {"registered", 1}
             ]
    end

    test "stay in order when steps are seconds rather than minutes apart" do
      # Comparing `DateTime` structs with the default sorter falls back to Erlang term
      # order, which ranks the struct's fields alphabetically — putting `microsecond`
      # ahead of `minute` and `second`. Timestamps that differ below the minute, which is
      # every real session, then sort essentially at random.
      AbFunnel.TestRepo.insert!(event("a", "landing", ~U[2026-08-01 12:00:01.900000Z]))
      AbFunnel.TestRepo.insert!(event("a", "generated", ~U[2026-08-01 12:00:09.100000Z]))
      AbFunnel.TestRepo.insert!(event("a", "registered", ~U[2026-08-01 12:01:00.050000Z]))

      assert report() |> steps("flow", "control") |> Enum.map(&elem(&1, 0)) ==
               ~w(landing generated registered)
    end
  end

  describe "counts are people, not events" do
    test "generating three codes counts once at that step" do
      record("a", "landing", 0, @control)
      record("a", "generated", 1, @control)
      record("a", "generated", 2, @control)
      record("a", "generated", 3, @control)

      assert report() |> steps("flow", "control") == [{"landing", 1}, {"generated", 1}]
    end

    test "two browsers bound to one person read as one person" do
      # The phone runs the anonymous flow and asks for a magic link. Days later the laptop
      # arrives fresh, lands, logs in and makes a code. One human, one journey.
      journey("phone", ~w(landing generate_submitted signup_requested), @control)
      journey("laptop", ~w(landing registered generated_as_user), @control, 10)

      AbFunnel.identify("phone", "person-a")
      AbFunnel.identify("laptop", "person-a")

      assert report() |> steps("flow", "control") == [
               {"landing", 1},
               {"generate_submitted", 1},
               {"signup_requested", 1},
               {"registered", 1},
               {"generated_as_user", 1}
             ]
    end

    test "without the binding the same data double-counts the top of the funnel" do
      journey("phone", ~w(landing generate_submitted), @control)
      journey("laptop", ~w(landing registered), @control, 10)

      steps = report() |> steps("flow", "control") |> Map.new()

      assert steps["landing"] == 2
      assert steps["registered"] == 1
    end

    test "binding is retroactive over events written before it" do
      journey("phone", ~w(landing generated), @control)
      record("laptop", "registered", 10, @control)

      AbFunnel.identify("phone", "person-a")
      AbFunnel.identify("laptop", "person-a")

      assert arm(report(), "flow", "control").exposed == 1
    end
  end

  describe "variant attribution" do
    test "a person on two devices lands in the arm they were assigned first" do
      # Assignment is per browser, so a person on a phone and a laptop is rolled twice and
      # lands in different arms about half the time. Left alone they show up as two
      # half-finished journeys in two different variants — which is precisely the
      # comparison an A/B test exists to make, quietly corrupted.
      journey("phone", ~w(landing generated), @control)
      journey("laptop", ~w(registered generated_as_user), @treatment, 10)

      AbFunnel.identify("phone", "person-a")
      AbFunnel.identify("laptop", "person-a")

      assert arm(report(), "flow", "control").exposed == 1
      assert arm(report(), "flow", "treatment").exposed == 0
      assert report() |> steps("flow", "control") |> Map.new() |> Map.get("registered") == 1
    end

    test "genuinely separate people keep their own arms" do
      journey("phone", ~w(landing generated), @control)
      journey("laptop", ~w(registered generated_as_user), @treatment, 10)

      assert arm(report(), "flow", "control").exposed == 1
      assert arm(report(), "flow", "treatment").exposed == 1
    end
  end

  describe "concurrent experiments" do
    test "one person contributes to every experiment they are in, independently" do
      both = Map.merge(@features, %{"pricing" => "annual"})
      journey("a", ~w(deck_started slide_f_intro), both)

      assert arm(report(), "deck", "features").exposed == 1
      assert arm(report(), "pricing", "annual").exposed == 1
    end

    test "an experiment someone is not in does not see them" do
      journey("a", ~w(deck_started slide_f_intro), @features)

      assert arm(report(), "pricing", "annual").exposed == 0
      assert arm(report(), "pricing", "monthly").exposed == 0
    end
  end

  describe "source attribution" do
    test "first touch wins when a person arrives from two places" do
      record("phone", "source:google", 0, @control)
      record("phone", "landing", 1, @control)
      record("laptop", "source:twitter", 10, @control)
      record("laptop", "registered", 11, @control)

      AbFunnel.identify("phone", "person-a")
      AbFunnel.identify("laptop", "person-a")

      # One person, one source, so there is nothing to break the funnel out by.
      assert sources_of(report(), "flow") == []
      assert arm(report(), "flow", "control").exposed == 1
    end

    test "source events are never funnel steps" do
      record("a", "source:google", 0, @control)
      record("a", "landing", 1, @control)

      assert report() |> steps("flow", "control") == [{"landing", 1}]
    end

    test "a funnel is broken out by source once there is more than one" do
      record("a", "source:google", 0, @control)
      journey("a", ~w(landing registered), @control, 1)
      journey("b", ~w(landing), @control, 10)

      sources = report() |> sources_of("flow") |> Enum.map(& &1.source) |> Enum.sort()

      assert sources == ["direct", "google"]
    end
  end

  describe "people who forced their own bucket" do
    test "are excluded, so a developer clicking through does not enter the numbers" do
      journey("real", ~w(deck_started slide_f_intro), @features)
      journey("dev", ~w(deck_started slide_f_intro), Map.put(@features, "$qa", "1"))

      assert arm(report(), "deck", "features").exposed == 1
    end
  end

  describe "the empty case" do
    test "no events at all is an empty report, not a crash" do
      report = report()

      assert Enum.map(report.experiments, & &1.key) == ["deck", "flow", "pricing"]
      assert Enum.all?(report.experiments, &(&1.exposed == 0))
      assert experiment(report, "deck").verdict.state == :no_goal
    end
  end

  describe "the window" do
    test "events older than it are not read" do
      journey("a", ~w(landing generated), @control)

      report = report(since: ~U[2026-08-02 00:00:00.000000Z])

      assert Enum.all?(report.experiments, &(&1.exposed == 0))
    end
  end
end
