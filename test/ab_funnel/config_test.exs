defmodule AbFunnel.ConfigTest do
  @moduledoc """
  The config keys an app is expected to override.

  Each of these is read once, deep inside a request, and getting one wrong fails silently:
  the wrong `person_key` splits one person into two, the wrong `current_user_assign` binds
  nobody at all. Neither raises.
  """
  use AbFunnel.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias AbFunnel.Services.Identities

  defp put_config(key, value) do
    previous = Application.fetch_env(:ab_funnel, key)
    Application.put_env(:ab_funnel, key, value)

    on_exit(fn ->
      case previous do
        {:ok, was} -> Application.put_env(:ab_funnel, key, was)
        :error -> Application.delete_env(:ab_funnel, key)
      end
    end)
  end

  defp visit(assigns) do
    :get
    |> conn("/")
    |> init_test_session(%{})
    |> then(fn conn -> Enum.reduce(assigns, conn, fn {k, v}, acc -> assign(acc, k, v) end) end)
    |> AbFunnel.Plug.Visitor.call([])
  end

  describe "person_key" do
    test "an app keyed on something other than email supplies its own" do
      put_config(:person_key, {__MODULE__, :account_key, 1})

      conn = visit(%{current_user: %{email: "krister@example.com", account_id: 42}})

      assert Identities.lookup() == %{conn.assigns.ab_funnel_visitor_id => "account:42"}
    end

    def account_key(%{account_id: id}), do: "account:#{id}"

    test "the default hashes the email, so the table holds no addresses" do
      key = AbFunnel.person_key("krister@example.com")

      refute key =~ "krister"
      assert String.length(key) == 64
    end

    test "the default normalises, so a typed address matches the stored one" do
      assert AbFunnel.person_key_for(%{email: " Krister@Example.com "}) ==
               AbFunnel.person_key("krister@example.com")
    end
  end

  describe "current_user_assign" do
    test "an app whose signed-in user is not @current_user still binds automatically" do
      put_config(:current_user_assign, :current_admin)

      conn = visit(%{current_admin: %{email: "admin@example.com"}})

      assert Identities.lookup() == %{
               conn.assigns.ab_funnel_visitor_id => AbFunnel.person_key("admin@example.com")
             }
    end

    test "the assign it is not looking at is ignored" do
      put_config(:current_user_assign, :current_admin)

      visit(%{current_user: %{email: "krister@example.com"}})

      assert Identities.lookup() == %{}
    end
  end

  describe "a missing experiments module" do
    test "says what to add rather than failing on a nil module" do
      put_config(:experiments, nil)
      put_config(:variants, nil)
      Application.delete_env(:ab_funnel, :experiments)
      Application.delete_env(:ab_funnel, :variants)

      assert_raise RuntimeError, ~r/config :ab_funnel, experiments:/, fn ->
        AbFunnel.Experiments.all()
      end
    end
  end
end
