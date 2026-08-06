defmodule AbFunnel.TrackTest do
  @moduledoc """
  `track/3` takes whatever the caller is holding and never gets in the way of what they
  were actually doing — no visitor is a quiet no-op, not an exception raised halfway
  through a controller action.
  """
  use AbFunnel.DataCase, async: true

  alias AbFunnel.Services.Events

  defp socket(opts) do
    %Phoenix.LiveView.Socket{
      transport_pid: if(opts[:connected], do: self()),
      assigns: Map.merge(%{__changed__: %{}}, Map.new(opts[:assigns] || []))
    }
  end

  describe "from a LiveView" do
    test "records on the connected mount" do
      socket =
        socket(
          connected: true,
          assigns: [ab_funnel_visitor_id: "v1", ab_funnel_assignments: %{"deck" => "features"}]
        )

      assert {:ok, event} = AbFunnel.track(socket, "deck_started")
      assert event.assignments == %{"deck" => "features"}
    end

    test "skips the dead render, so a mount does not write everything twice" do
      # A LiveView mounts once over HTTP to render the page and again over the socket.
      # Tracking on both doubles every event in the table.
      socket = socket(assigns: [ab_funnel_visitor_id: "v1", ab_funnel_assignments: %{}])

      assert AbFunnel.track(socket, "deck_started") == {:ok, :not_connected}
      assert Events.all() == []
    end
  end

  describe "from anything else" do
    test "a conn works the same way" do
      conn = %{assigns: %{ab_funnel_visitor_id: "v1", ab_funnel_assignments: %{}}}

      assert {:ok, event} = AbFunnel.track(conn, "checked_out", %{"plan" => "pro"})
      assert event.metadata == %{"plan" => "pro"}
    end

    test "no visitor is a no-op rather than an exception" do
      assert AbFunnel.track(%{assigns: %{}}, "landing") == {:ok, :no_visitor}
      assert AbFunnel.identify(%{assigns: %{}}, "person-a") == {:ok, :no_visitor}
      assert Events.all() == []
    end
  end

  describe "variant/2" do
    test "answers for a named experiment" do
      conn = %{assigns: %{ab_funnel_assignments: %{"deck" => "features", "pricing" => "annual"}}}

      assert AbFunnel.variant(conn, :pricing) == "annual"
      assert AbFunnel.variant(conn, "deck") == "features"
      assert AbFunnel.variant(conn, :nonexistent) == nil
    end

    test "defaults to the first experiment, for an app running only one" do
      conn = %{assigns: %{ab_funnel_assignments: %{"deck" => "features"}}}

      assert AbFunnel.variant(conn) == "features"
    end

    test "is nil rather than a crash when the plug never ran" do
      assert AbFunnel.variant(%{assigns: %{}}, :deck) == nil
      assert AbFunnel.variant(nil, :deck) == nil
    end
  end
end
