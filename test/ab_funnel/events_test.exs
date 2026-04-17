defmodule AbFunnel.EventsTest do
  use AbFunnel.DataCase, async: true

  test "track/3 inserts an event" do
    {:ok, event} = AbFunnel.Events.track("visitor-1", "landed", "control")

    assert event.visitor_id == "visitor-1"
    assert event.event == "landed"
    assert event.variant == "control"
    assert event.metadata == %{}
  end

  test "track/4 stores metadata" do
    {:ok, event} = AbFunnel.Events.track("visitor-1", "landed", "control", %{"page" => "/home"})
    assert event.metadata == %{"page" => "/home"}
  end

  test "duplicate events are stored (no dedup)" do
    {:ok, _} = AbFunnel.Events.track("visitor-1", "landed", "control")
    {:ok, _} = AbFunnel.Events.track("visitor-1", "landed", "control")

    events = AbFunnel.Events.all()
    visitor_landed = Enum.filter(events, &(&1.visitor_id == "visitor-1" and &1.event == "landed"))
    assert length(visitor_landed) == 2
  end

  test "all/0 returns all events" do
    {:ok, _} = AbFunnel.Events.track("v1", "landed", "control")
    {:ok, _} = AbFunnel.Events.track("v2", "clicked", "treatment")

    events = AbFunnel.Events.all()
    assert length(events) >= 2
  end
end
