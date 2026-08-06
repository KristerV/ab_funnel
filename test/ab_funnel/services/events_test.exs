defmodule AbFunnel.Services.EventsTest do
  use AbFunnel.DataCase, async: true

  alias AbFunnel.Services.Events

  test "an event carries every bucket the visitor is in" do
    {:ok, event} =
      Events.track("visitor-1", "landed", %{"deck" => "features", "pricing" => "annual"})

    assert event.visitor_id == "visitor-1"
    assert event.event == "landed"
    assert event.assignments == %{"deck" => "features", "pricing" => "annual"}
    assert event.metadata == %{}
  end

  test "a bare variant is attributed to the experiment that declares it" do
    # The shape single-experiment callers used before experiments existed.
    {:ok, event} = Events.track("visitor-1", "landed", "solving_emails")

    assert event.assignments == %{"deck" => "solving_emails"}
  end

  test "a variant nobody declares lands in no experiment rather than a phantom one" do
    {:ok, event} = Events.track("visitor-1", "landed", "who-knows")

    assert event.assignments == %{}
  end

  test "metadata is stored alongside" do
    {:ok, event} = Events.track("visitor-1", "landed", %{}, %{"page" => "/home"})

    assert event.metadata == %{"page" => "/home"}
  end

  test "the log is append-only — nothing is deduplicated on the way in" do
    # Dedup happens at read time, per person per step. Doing it on write would lose the
    # count of how often someone repeated a step, which is a real question to ask later.
    {:ok, _} = Events.track("visitor-1", "landed", %{})
    {:ok, _} = Events.track("visitor-1", "landed", %{})

    assert length(Events.all()) == 2
  end

  test "prune/1 bounds the table for an app that wants it bounded" do
    record("old", "landed", 0)

    assert {1, _} = Events.prune(1)
    assert Events.all() == []
  end
end
