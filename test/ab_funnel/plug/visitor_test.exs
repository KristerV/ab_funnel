defmodule AbFunnel.Plug.VisitorTest do
  @moduledoc """
  What the plug puts on a browser, and what it refuses to.

  This runs on every request of every visitor, so it is both the place stickiness has to
  hold and the place a crafted URL or an edited cookie would get its foot in the door.
  """
  use AbFunnel.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias AbFunnel.Assignment
  alias AbFunnel.Services.Events

  defp visit(path \\ "/", opts \\ []) do
    :get
    |> conn(path)
    |> then(fn conn ->
      Enum.reduce(opts[:cookies] || %{}, conn, fn {k, v}, acc -> put_req_cookie(acc, k, v) end)
    end)
    |> then(fn conn ->
      if agent = opts[:user_agent], do: put_req_header(conn, "user-agent", agent), else: conn
    end)
    |> then(fn conn -> if prev = opts[:after], do: recycle_cookies(conn, prev), else: conn end)
    |> init_test_session(%{})
    |> AbFunnel.Plug.Visitor.call([])
  end

  defp cookie(conn, name), do: conn.resp_cookies[name] && conn.resp_cookies[name].value
  defp event_names, do: Events.all() |> Enum.map(& &1.event)

  describe "a first visit" do
    test "gets a visitor id and a bucket in every running experiment" do
      conn = visit()

      assert is_binary(cookie(conn, "ab_funnel_visitor_id"))

      assert Map.keys(conn.assigns.ab_funnel_assignments) |> Enum.sort() ==
               ["deck", "flow", "pricing"]
    end

    test "stores the assignments in one cookie, not one each" do
      conn = visit()

      assert Assignment.decode(cookie(conn, "ab_funnel_assignments")) ==
               conn.assigns.ab_funnel_assignments
    end

    test "exposes the first experiment as @ab_funnel_variant, for single-test apps" do
      conn = visit()

      assert conn.assigns.ab_funnel_variant == conn.assigns.ab_funnel_assignments["deck"]
    end
  end

  describe "a returning visit" do
    test "keeps the same buckets and rewrites nothing" do
      first = visit()
      second = visit("/", after: first)

      assert second.assigns.ab_funnel_assignments == first.assigns.ab_funnel_assignments
      refute cookie(second, "ab_funnel_visitor_id")
      refute cookie(second, "ab_funnel_assignments")
    end

    test "is assigned into an experiment that did not exist when they first arrived" do
      partial = Assignment.encode(%{"deck" => "features"})
      conn = visit("/", cookies: %{"ab_funnel_assignments" => partial})

      assert conn.assigns.ab_funnel_assignments["deck"] == "features"
      assert conn.assigns.ab_funnel_assignments["pricing"] in ["monthly", "annual"]
      assert cookie(conn, "ab_funnel_assignments")
    end
  end

  describe "upgrading from the single-variant cookie" do
    test "an existing ab_funnel_variant is honoured rather than rerolled" do
      # Everyone mid-experiment when the library is upgraded has one of these. Ignoring it
      # would rebucket the entire live test at deploy time.
      conn = visit("/", cookies: %{"ab_funnel_variant" => "solving_emails"})

      assert conn.assigns.ab_funnel_assignments["deck"] == "solving_emails"
    end

    test "a variant nobody declares is discarded" do
      conn = visit("/", cookies: %{"ab_funnel_variant" => "i-picked-this"})

      assert conn.assigns.ab_funnel_assignments["deck"] in ["features", "solving_emails"]
    end
  end

  describe "assignment is not client-controlled" do
    test "an edited assignments cookie is replaced with a real assignment" do
      forged = Assignment.encode(%{"deck" => "i-picked-this"})
      conn = visit("/", cookies: %{"ab_funnel_assignments" => forged})

      assert conn.assigns.ab_funnel_assignments["deck"] in ["features", "solving_emails"]
    end

    test "nothing tracked under a made-up variant reaches the table" do
      forged = Assignment.encode(%{"deck" => "i-picked-this"})
      conn = visit("/", cookies: %{"ab_funnel_assignments" => forged})
      AbFunnel.track(conn, "deck_started")

      [event] = Events.all()
      refute event.assignments["deck"] == "i-picked-this"
    end
  end

  describe "the QA override" do
    test "forces a bucket so the other arm can be looked at" do
      conn = visit("/?ab_funnel=deck:solving_emails")

      assert conn.assigns.ab_funnel_assignments["deck"] == "solving_emails"
    end

    test "sticks for the rest of the session" do
      first = visit("/?ab_funnel=deck:solving_emails")
      second = visit("/", after: first)

      assert second.assigns.ab_funnel_assignments["deck"] == "solving_emails"
    end

    test "marks everything that visitor does, so the report can drop them" do
      # Without this the override is a hole straight through the experiment: the person
      # most likely to force a bucket is the one about to read the numbers.
      conn = visit("/?ab_funnel=deck:solving_emails")
      AbFunnel.track(conn, "deck_started")

      [event] = Events.all()
      assert Assignment.qa?(event.assignments)
    end

    test "clears with ?ab_funnel=off" do
      first = visit("/?ab_funnel=deck:solving_emails")
      second = visit("/?ab_funnel=off", after: first)

      refute Assignment.qa?(second.assigns.ab_funnel_assignments)
    end

    test "cannot be used to invent a variant" do
      conn = visit("/?ab_funnel=deck:i-picked-this")

      assert conn.assigns.ab_funnel_assignments["deck"] in ["features", "solving_emails"]
      refute Assignment.qa?(conn.assigns.ab_funnel_assignments)
    end
  end

  describe "crawlers" do
    @googlebot "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

    test "get no cookies and no visitor id" do
      conn = visit("/", user_agent: @googlebot)

      assert conn.assigns.ab_funnel_bot
      assert conn.assigns.ab_funnel_visitor_id == nil
      assert conn.resp_cookies == %{}
    end

    test "still render something, on the control arm" do
      conn = visit("/", user_agent: @googlebot)

      assert conn.assigns.ab_funnel_variant == "features"
    end

    test "write nothing, so they never touch the numbers" do
      conn = visit("/?utm_source=linkedin", user_agent: @googlebot)
      AbFunnel.track(conn, "deck_started")

      assert event_names() == []
    end
  end
end
