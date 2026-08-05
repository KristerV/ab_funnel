defmodule AbFunnel.AutoIdentifyTest do
  @moduledoc """
  Binding a browser to whoever is signed in, without the host app asking.

  This is the part apps used to have to remember, in every place someone could
  authenticate — and forgetting any one of them broke cross-device funnels silently. If
  it regresses, nothing raises; the numbers just quietly go wrong.
  """
  use AbFunnel.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias AbFunnel.Services.Identities

  defp call(conn), do: AbFunnel.Plug.Visitor.call(conn, [])

  defp browser(assigns \\ %{}) do
    :get
    |> conn("/")
    |> init_test_session(%{})
    |> then(fn conn -> Enum.reduce(assigns, conn, fn {k, v}, c -> assign(c, k, v) end) end)
  end

  describe "the plug" do
    test "binds a signed-in visitor to their email" do
      conn = call(browser(%{current_user: %{email: "krister@example.com"}}))

      visitor_id = conn.assigns.ab_funnel_visitor_id

      assert Identities.lookup() == %{
               visitor_id => AbFunnel.person_key("krister@example.com")
             }
    end

    test "leaves an anonymous visitor unbound" do
      call(browser())

      assert Identities.lookup() == %{}
    end

    test "assigns the visitor so track/2 works on a conn" do
      conn = call(browser())

      assert is_binary(conn.assigns.ab_funnel_visitor_id)
      assert is_binary(conn.assigns.ab_funnel_variant)

      {:ok, event} = AbFunnel.track(conn, "checked_out")

      assert event.visitor_id == conn.assigns.ab_funnel_visitor_id
      assert event.event == "checked_out"
    end

    test "does not write a binding again on the next request of the same session" do
      user = %{current_user: %{email: "krister@example.com"}}
      conn = call(browser(user))

      identity = Identities.all() |> List.first()

      # Same session, same user: a page view should not cost a write.
      conn
      |> recycle_session()
      |> then(fn c -> Enum.reduce(user, c, fn {k, v}, acc -> assign(acc, k, v) end) end)
      |> call()

      assert [^identity] = Identities.all()
    end

    test "rebinds when a different person signs in on the same browser" do
      conn = call(browser(%{current_user: %{email: "first@example.com"}}))
      visitor_id = conn.assigns.ab_funnel_visitor_id

      conn
      |> recycle_session()
      |> assign(:current_user, %{email: "second@example.com"})
      |> call()

      assert Identities.lookup() == %{visitor_id => AbFunnel.person_key("second@example.com")}
    end
  end

  describe "person_key_for/1" do
    test "prefers email, and matches a key derived from a typed-in address" do
      assert AbFunnel.person_key_for(%{email: "Krister@Example.com "}) ==
               AbFunnel.person_key("krister@example.com")
    end

    test "falls back to id when there is no email" do
      assert AbFunnel.person_key_for(%{id: 42}) == "id:42"
    end

    test "handles a wrapped email type rather than stringifying the struct" do
      # Ash apps hold a `Ash.CiString` here; anything with a String.Chars impl must
      # produce the same key as the plain address would.
      assert AbFunnel.person_key_for(%{email: %AbFunnel.FakeCiString{value: "a@b.com"}}) ==
               AbFunnel.person_key("a@b.com")
    end

    test "is nil for something with neither, rather than crashing the request" do
      assert AbFunnel.person_key_for(%{name: "nobody"}) == nil
    end
  end

  describe "track/2 and identify/2 without a visitor" do
    test "are quiet no-ops rather than raising mid-request" do
      assert AbFunnel.track(%{assigns: %{}}, "landing") == {:ok, :no_visitor}
      assert AbFunnel.identify(%{assigns: %{}}, "person-a") == {:ok, :no_visitor}
      assert AbFunnel.Services.Events.all() == []
    end
  end

  # The next request from the same browser: both the cookies (so the visitor id survives)
  # and the session (so the "already bound" marker the plug wrote is visible).
  defp recycle_session(conn) do
    session = conn.private[:plug_session] || %{}

    :get
    |> conn("/")
    |> recycle_cookies(conn)
    |> init_test_session(session)
  end
end
