defmodule AbFunnel.Plug.Visitor do
  import Plug.Conn

  @max_age 365 * 24 * 60 * 60

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> fetch_cookies() |> fetch_query_params()

    {conn, visitor_id} =
      ensure_cookie(conn, "ab_funnel_visitor_id", fn -> Ecto.UUID.generate() end)

    variants_mod = AbFunnel.variants_module()

    {conn, variant} =
      ensure_cookie(conn, "ab_funnel_variant", fn ->
        Atom.to_string(variants_mod.random_key())
      end)

    utm_source = conn.query_params["utm_source"]
    utm_campaign = conn.query_params["utm_campaign"]

    {conn, source} =
      ensure_cookie(conn, "ab_funnel_source", fn ->
        case {utm_source, utm_campaign} do
          {nil, nil} -> "direct"
          {s, nil} -> s
          {nil, c} -> c
          {s, c} -> "#{s}/#{c}"
        end
      end)

    if source != "direct" do
      AbFunnel.track(visitor_id, "source:#{source}", variant)
    end

    conn
    |> put_session("ab_funnel_visitor_id", visitor_id)
    |> put_session("ab_funnel_variant", variant)
    |> put_session("ab_funnel_source", source)
  end

  defp ensure_cookie(conn, name, generator) do
    case conn.cookies[name] do
      nil ->
        value = generator.()
        conn = put_resp_cookie(conn, name, value, max_age: @max_age, same_site: "Lax")
        {conn, value}

      value ->
        {conn, value}
    end
  end
end
