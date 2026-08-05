defmodule AbFunnel.Services.IdentitiesTest do
  @moduledoc """
  Binding browsers to people. If this regresses, any funnel that crosses a login boundary
  silently splits one person into two half-finished journeys.
  """
  use AbFunnel.DataCase, async: true

  alias AbFunnel.Services.Identities

  describe "identify/2" do
    test "binds a visitor to a person" do
      {:ok, identity} = Identities.identify("visitor-1", "person-a")

      assert identity.visitor_id == "visitor-1"
      assert identity.person_key == "person-a"
    end

    test "is idempotent — identifying twice with the same key leaves one row" do
      {:ok, _} = Identities.identify("visitor-1", "person-a")
      {:ok, _} = Identities.identify("visitor-1", "person-a")

      assert Identities.lookup() == %{"visitor-1" => "person-a"}
    end

    test "rebinds on a new key, so a corrected email wins over the typo" do
      {:ok, _} = Identities.identify("visitor-1", "typo-key")
      {:ok, _} = Identities.identify("visitor-1", "person-a")

      assert Identities.lookup() == %{"visitor-1" => "person-a"}
    end

    test "many visitors can share one person — that is the entire point" do
      {:ok, _} = Identities.identify("phone", "person-a")
      {:ok, _} = Identities.identify("laptop", "person-a")
      {:ok, _} = Identities.identify("webview", "person-a")

      assert Identities.lookup() == %{
               "phone" => "person-a",
               "laptop" => "person-a",
               "webview" => "person-a"
             }
    end
  end

  describe "lookup/0" do
    test "is empty when nobody has been identified" do
      assert Identities.lookup() == %{}
    end
  end

  describe "person_key/1" do
    test "normalises case and surrounding whitespace" do
      assert AbFunnel.person_key("  Krister@Example.COM ") ==
               AbFunnel.person_key("krister@example.com")
    end

    test "differs between addresses" do
      refute AbFunnel.person_key("a@example.com") == AbFunnel.person_key("b@example.com")
    end

    test "does not contain the address it was derived from" do
      key = AbFunnel.person_key("krister@example.com")

      refute key =~ "krister"
      refute key =~ "example.com"
    end
  end

  describe "AbFunnel.identify/2" do
    test "delegates for a raw visitor id" do
      {:ok, _} = AbFunnel.identify("visitor-1", AbFunnel.person_key("krister@example.com"))

      assert Identities.lookup() == %{
               "visitor-1" => AbFunnel.person_key("krister@example.com")
             }
    end
  end
end
