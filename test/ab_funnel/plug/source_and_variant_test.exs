defmodule AbFunnel.Plug.SourceAndVariantTest do
  @moduledoc """
  What the visitor plug writes, and what it refuses to write.

  Both halves matter for a library that stores rows on every request: attribution must be
  recorded once rather than per page view, and neither the event table nor the variant
  column should be writable by whoever crafts the URL or edits their cookies.
  """
  use AbFunnel.DataCase, async: false

  import Plug.Test

  alias AbFunnel.Services.Events

  defp visit(path, opts \\ []) do
    :get
    |> conn(path)
    |> then(fn c ->
      Enum.reduce(opts[:cookies] || %{}, c, fn {k, v}, acc -> put_req_cookie(acc, k, v) end)
    end)
    |> then(fn c -> if prev = opts[:after], do: recycle_cookies(c, prev), else: c end)
    |> init_test_session(%{})
    |> AbFunnel.Plug.Visitor.call([])
  end

  defp event_names, do: Events.all() |> Enum.map(& &1.event)

  describe "source attribution" do
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
  end

  describe "source values are not trusted" do
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

  describe "variant assignment is not client-controlled" do
    test "an unrecognised variant cookie is replaced with a real assignment" do
      conn = visit("/", cookies: %{"ab_funnel_variant" => "i-picked-this"})

      refute conn.assigns.ab_funnel_variant == "i-picked-this"
      assert AbFunnel.TestVariants.known?(conn.assigns.ab_funnel_variant)
      assert conn.resp_cookies["ab_funnel_variant"]
    end

    test "nothing tracked under a made-up variant reaches the table" do
      conn = visit("/", cookies: %{"ab_funnel_variant" => "i-picked-this"})
      AbFunnel.track(conn, "landing")

      [event] = Events.all()
      refute event.variant == "i-picked-this"
    end

    test "a legitimate assignment is left alone" do
      conn = visit("/", cookies: %{"ab_funnel_variant" => "treatment"})

      assert conn.assigns.ab_funnel_variant == "treatment"
      refute conn.resp_cookies["ab_funnel_variant"]
    end

    test "a retired variant is still honoured for whoever already has it" do
      # Turning a variant off stops new assignments; it must not silently reroll people
      # mid-experiment, which would put their before and after in different buckets.
      conn = visit("/", cookies: %{"ab_funnel_variant" => "old"})

      assert conn.assigns.ab_funnel_variant == "old"
    end
  end

  describe "misconfiguration" do
    test "no active variants fails with a message that says what to do" do
      assert_raise RuntimeError, ~r/no active variants/, fn ->
        AbFunnel.InactiveVariants.random_key()
      end
    end
  end
end
