defmodule AbFunnel.Plug.VisitorTest do
  use AbFunnel.DataCase, async: false
  import Plug.Test

  alias AbFunnel.Plug.Visitor

  defp call_plug(conn) do
    conn
    |> init_test_session(%{})
    |> Visitor.call(Visitor.init([]))
  end

  test "assigns visitor_id, variant, and source cookies on first visit" do
    conn =
      conn(:get, "/")
      |> call_plug()

    assert conn.resp_cookies["ab_funnel_visitor_id"]
    assert conn.resp_cookies["ab_funnel_variant"]
    assert conn.resp_cookies["ab_funnel_source"]

    visitor_id = conn.resp_cookies["ab_funnel_visitor_id"].value
    variant = conn.resp_cookies["ab_funnel_variant"].value
    source = conn.resp_cookies["ab_funnel_source"].value

    assert byte_size(visitor_id) > 0
    assert variant in ["control", "treatment"]
    assert source == "direct"
  end

  test "preserves existing cookies on returning visit" do
    conn =
      conn(:get, "/")
      |> put_req_cookie("ab_funnel_visitor_id", "existing-id")
      |> put_req_cookie("ab_funnel_variant", "control")
      |> put_req_cookie("ab_funnel_source", "direct")
      |> call_plug()

    refute conn.resp_cookies["ab_funnel_visitor_id"]
    refute conn.resp_cookies["ab_funnel_variant"]
  end

  test "captures utm_source into source cookie" do
    conn =
      conn(:get, "/?utm_source=linkedin")
      |> call_plug()

    assert conn.resp_cookies["ab_funnel_source"].value == "linkedin"
  end

  test "captures utm_source/utm_campaign combo" do
    conn =
      conn(:get, "/?utm_source=google&utm_campaign=retarget")
      |> call_plug()

    assert conn.resp_cookies["ab_funnel_source"].value == "google/retarget"
  end

  test "fires source event for non-direct visitors" do
    conn =
      conn(:get, "/?utm_source=twitter")
      |> call_plug()

    visitor_id = conn.resp_cookies["ab_funnel_visitor_id"].value

    events = AbFunnel.Services.Events.all()

    source_events =
      Enum.filter(events, &(&1.visitor_id == visitor_id and &1.event == "source:twitter"))

    assert length(source_events) >= 1
  end

  test "does not fire source event for direct visitors" do
    conn =
      conn(:get, "/")
      |> call_plug()

    visitor_id = conn.resp_cookies["ab_funnel_visitor_id"].value

    events = AbFunnel.Services.Events.all()

    source_events =
      Enum.filter(
        events,
        &(&1.visitor_id == visitor_id and String.starts_with?(&1.event, "source:"))
      )

    assert source_events == []
  end
end
