defmodule AbFunnel.MultiExperimentTest do
  @moduledoc """
  One person, several experiments at once — the whole loop, from a real request through
  the plug to what the report says about them.

  The unit tests either side of this seam both pass while it is broken: the plug can hand
  out three buckets, the report can count three experiments, and the events in between can
  still carry the wrong thing. Nothing raises when they disagree — the arms just come out
  short, which reads as "not many people yet" rather than as a bug.
  """
  use AbFunnel.DataCase, async: false

  import Plug.Test

  alias AbFunnel.Services.Events

  defp visit(path \\ "/", previous \\ nil) do
    :get
    |> conn(path)
    |> then(fn conn -> if previous, do: recycle_cookies(conn, previous), else: conn end)
    |> init_test_session(%{})
    |> AbFunnel.Plug.Visitor.call([])
  end

  describe "a single visit" do
    test "puts one person into every running experiment at once" do
      conn = visit()
      AbFunnel.track(conn, "deck_started")
      AbFunnel.track(conn, "lead_submitted")

      report = report()
      assigned = conn.assigns.ab_funnel_assignments

      for experiment <- ~w(deck flow pricing) do
        assert arm(report, experiment, assigned[experiment]).exposed == 1,
               "expected the visitor to be counted in #{experiment}"
      end
    end

    test "records one row per event, carrying every bucket" do
      # Not one row per experiment. Fanning out would multiply writes by the number of
      # running tests and make "how many events" meaningless.
      conn = visit()
      AbFunnel.track(conn, "deck_started")

      assert [event] = Events.all()
      assert Map.keys(event.assignments) |> Enum.sort() == ~w(deck flow pricing)
    end

    test "counts the person once per experiment, not once per experiment they are in" do
      conn = visit()
      AbFunnel.track(conn, "deck_started")

      assert experiment(report(), "deck").exposed == 1
      assert experiment(report(), "pricing").exposed == 1
    end
  end

  describe "declaring a second experiment on a live app" do
    test "a visitor who was already active joins it on their next visit" do
      # Monday: only :deck is declared, so that is all their events can carry.
      record("krister", "deck_started", 0, %{"deck" => "features"})

      # Tuesday: :pricing is declared. Their next event carries both.
      record("krister", "lead_submitted", 10, %{"deck" => "features", "pricing" => "annual"})

      assert arm(report(), "pricing", "annual").exposed == 1
    end

    test "and keeps the arm they already had in the first one" do
      record("krister", "deck_started", 0, %{"deck" => "features"})
      record("krister", "lead_submitted", 10, %{"deck" => "features", "pricing" => "annual"})

      assert arm(report(), "deck", "features").exposed == 1
      assert arm(report(), "deck", "solving_emails").exposed == 0
    end

    test "the plug assigns them into it without touching their existing buckets" do
      held = AbFunnel.Assignment.encode(%{"deck" => "features", "flow" => "control"})

      conn =
        :get
        |> conn("/")
        |> put_req_cookie("ab_funnel_assignments", held)
        |> init_test_session(%{})
        |> AbFunnel.Plug.Visitor.call([])

      assert conn.assigns.ab_funnel_assignments["deck"] == "features"
      assert conn.assigns.ab_funnel_assignments["flow"] == "control"
      assert conn.assigns.ab_funnel_assignments["pricing"] in ~w(monthly annual)
    end
  end

  describe "across devices" do
    test "each experiment resolves its own earliest assignment, independently" do
      # The phone was around before :pricing existed; the laptop is the only device that
      # has ever seen it. Their deck arm must come from the phone, their pricing arm from
      # the laptop — one rule, applied per experiment rather than per person.
      record("phone", "deck_started", 0, %{"deck" => "features"})

      record("laptop", "lead_submitted", 10, %{
        "deck" => "solving_emails",
        "pricing" => "annual"
      })

      AbFunnel.identify("phone", "krister")
      AbFunnel.identify("laptop", "krister")

      assert arm(report(), "deck", "features").exposed == 1
      assert arm(report(), "deck", "solving_emails").exposed == 0
      assert arm(report(), "pricing", "annual").exposed == 1
    end

    test "one journey, counted once, in every experiment it touched" do
      record("phone", "deck_started", 0, %{"deck" => "features", "pricing" => "annual"})
      record("laptop", "lead_submitted", 10, %{"deck" => "features", "pricing" => "annual"})

      AbFunnel.identify("phone", "krister")
      AbFunnel.identify("laptop", "krister")

      deck = arm(report(), "deck", "features")

      assert deck.exposed == 1
      assert deck.converted == 1
      assert arm(report(), "pricing", "annual").exposed == 1
    end
  end
end
