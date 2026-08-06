defmodule AbFunnel.LiveViewTest do
  @moduledoc """
  The `on_mount` hook, which is the only thing carrying assignments across the boundary
  between a request and a socket.

  If it silently assigns nothing, every LiveView still renders and every `track/2` still
  returns `{:ok, ...}` — the events simply stop arriving. Nothing raises, so nothing tells
  you. That is what these cover.
  """
  use AbFunnel.DataCase, async: false

  alias AbFunnel.Services.Identities

  defp mount(session, assigns \\ %{}) do
    socket = %Phoenix.LiveView.Socket{assigns: Map.put(assigns, :__changed__, %{})}

    {:cont, socket} = AbFunnel.LiveView.on_mount(:default, %{}, session, socket)
    socket
  end

  @session %{
    "ab_funnel_visitor_id" => "v1",
    "ab_funnel_assignments" => %{"deck" => "features", "pricing" => "annual"},
    "ab_funnel_source" => "linkedin"
  }

  describe "what lands in assigns" do
    test "carries the visitor, every assignment and the source across" do
      socket = mount(@session)

      assert socket.assigns.ab_funnel_visitor_id == "v1"

      assert socket.assigns.ab_funnel_assignments == %{
               "deck" => "features",
               "pricing" => "annual"
             }

      assert socket.assigns.ab_funnel_source == "linkedin"
    end

    test "exposes the first experiment as @ab_funnel_variant" do
      assert mount(@session).assigns.ab_funnel_variant == "features"
    end

    test "makes track/2 work from the socket" do
      socket = %{mount(@session) | transport_pid: self()}

      assert {:ok, event} = AbFunnel.track(socket, "deck_started")
      assert event.assignments == %{"deck" => "features", "pricing" => "annual"}
    end

    test "a mount with no session at all assigns nils rather than raising" do
      # A LiveView mounted outside the pipeline, or before the plug was added.
      socket = mount(%{})

      assert socket.assigns.ab_funnel_visitor_id == nil
      assert socket.assigns.ab_funnel_assignments == %{}
      assert socket.assigns.ab_funnel_variant == nil
    end
  end

  describe "binding a signed-in visitor" do
    test "happens here too, for a mount the plug never saw" do
      mount(@session, %{current_user: %{email: "krister@example.com"}})

      assert Identities.lookup() == %{"v1" => AbFunnel.person_key("krister@example.com")}
    end

    test "is skipped when the last request already bound them" do
      # The plug does this on every real request and leaves a marker. Repeating it on
      # every mount would be a write per LiveView navigation carrying nothing new.
      session =
        Map.put(@session, "ab_funnel_identified", AbFunnel.person_key("krister@example.com"))

      mount(session, %{current_user: %{email: "krister@example.com"}})

      assert Identities.lookup() == %{}
    end

    test "leaves an anonymous visitor unbound" do
      mount(@session)

      assert Identities.lookup() == %{}
    end
  end
end
