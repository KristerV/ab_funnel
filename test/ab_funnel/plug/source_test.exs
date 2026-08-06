defmodule AbFunnel.Plug.SourceTest do
  @moduledoc """
  Where a visitor came from.

  Attribution must be recorded once rather than per page view, and the value arrives from
  the URL — so it is also the one place a stranger gets to influence what ends up in the
  events table.
  """
  use AbFunnel.DataCase, async: false

  import Plug.Test

  alias AbFunnel.Services.Events

  defp visit(path, opts \\ []) do
    :get
    |> conn(path)
    |> then(fn conn -> if prev = opts[:after], do: recycle_cookies(conn, prev), else: conn end)
    |> init_test_session(%{})
    |> AbFunnel.Plug.Visitor.call([])
  end

  defp event_names, do: Events.all() |> Enum.map(& &1.event)

  describe "attribution" do
    test "is recorded once, not on every page view afterwards" do
      first = visit("/?utm_source=linkedin")
      second = visit("/", after: first)
      visit("/", after: second)

      # The cookie keeps them attributed for a year. Re-recording it each request would
      # grow the table in proportion to page views for no extra information.
      assert event_names() == ["source:linkedin"]
    end

    test "still applies to the visitor on later requests" do
      first = visit("/?utm_source=linkedin")
      later = visit("/", after: first)

      assert later.assigns.ab_funnel_source == "linkedin"
    end

    test "direct visits record nothing" do
      visit("/")

      assert event_names() == []
    end

    test "combines source and campaign" do
      visit("/?utm_source=google&utm_campaign=retarget")

      assert event_names() == ["source:google/retarget"]
    end

    test "carries the visitor's buckets, like any other event" do
      conn = visit("/?utm_source=linkedin")

      [event] = Events.all()
      assert event.assignments == conn.assigns.ab_funnel_assignments
    end
  end

  describe "values from the URL are not trusted" do
    test "a long utm cannot write an arbitrarily long event name" do
      visit("/?utm_source=#{String.duplicate("a", 500)}")

      [name] = event_names()
      assert String.length(name) < 100
    end

    test "punctuation and markup are stripped" do
      visit("/?utm_source=" <> URI.encode_www_form("<script>x</script>"))

      assert event_names() == ["source:scriptxscript"]
    end

    test "case is normalised so one campaign is one row" do
      visit("/?utm_source=LinkedIn")

      assert event_names() == ["source:linkedin"]
    end

    test "a utm that sanitises to nothing counts as direct" do
      visit("/?utm_source=" <> URI.encode_www_form("!!!"))

      assert event_names() == []
    end
  end
end
