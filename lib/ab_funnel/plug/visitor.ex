defmodule AbFunnel.Plug.Visitor do
  @moduledoc """
  Assigns every browser a visitor id and a variant, both sticky for a year, and records
  where they came from.

  Also binds the browser to whoever is signed in, so apps never have to remember to. Put
  this *after* whatever loads the current user, or that binding has nothing to work with.
  """
  import Plug.Conn

  @max_age 365 * 24 * 60 * 60

  # UTM values are arbitrary strings from the query string, and they end up in event
  # names. Cap and scrub them so a crafted link cannot write whatever it likes into the
  # events table.
  @max_source_length 48

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> fetch_cookies() |> fetch_query_params()

    {conn, visitor_id, _} =
      ensure_cookie(conn, "ab_funnel_visitor_id", fn -> Ecto.UUID.generate() end)

    variants_mod = AbFunnel.variants_module()

    {conn, variant, _} =
      ensure_cookie(
        conn,
        "ab_funnel_variant",
        fn -> Atom.to_string(variants_mod.random_key()) end,
        # A cookie is whatever the client says it is. An unrecognised variant would let a
        # visitor pick their own bucket and would show up as a phantom column in the
        # report, so anything we do not recognise is replaced with a fresh assignment.
        &variants_mod.known?/1
      )

    {conn, source, source_state} =
      ensure_cookie(conn, "ab_funnel_source", fn -> derive_source(conn) end)

    # Only on the request that established it. Firing whenever the cookie merely *exists*
    # writes a duplicate row on every subsequent page view, forever.
    if source_state == :new and source != "direct" do
      AbFunnel.track(visitor_id, "source:#{source}", variant)
    end

    conn
    |> put_session("ab_funnel_visitor_id", visitor_id)
    |> put_session("ab_funnel_variant", variant)
    |> put_session("ab_funnel_source", source)
    # Assigned as well as put in the session, so `AbFunnel.track(conn, ...)` reads them
    # from the same place it does on a socket.
    |> assign(:ab_funnel_visitor_id, visitor_id)
    |> assign(:ab_funnel_variant, variant)
    |> assign(:ab_funnel_source, source)
    |> maybe_identify(visitor_id)
  end

  defp derive_source(conn) do
    source = sanitize(conn.query_params["utm_source"])
    campaign = sanitize(conn.query_params["utm_campaign"])

    case {source, campaign} do
      {nil, nil} -> "direct"
      {s, nil} -> s
      {nil, c} -> c
      {s, c} -> "#{s}/#{c}"
    end
  end

  defp sanitize(nil), do: nil

  defp sanitize(value) when is_binary(value) do
    value
    |> String.slice(0, @max_source_length)
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]/u, "")
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  defp sanitize(_), do: nil

  # Binding is an upsert, and running one on every request of every signed-in session
  # would be a write per page view carrying no new information. The session remembers who
  # this browser was last bound to, so the write happens once per sign-in.
  defp maybe_identify(conn, visitor_id) do
    with user when not is_nil(user) <- AbFunnel.Context.current_user(conn),
         person_key when is_binary(person_key) <- AbFunnel.person_key_for(user),
         true <- get_session(conn, "ab_funnel_identified") != person_key,
         # Only remember it if it actually landed — marking a failed write as done would
         # skip the binding on every later request and leave the person unjoined.
         {:ok, _} <- AbFunnel.identify(visitor_id, person_key) do
      put_session(conn, "ab_funnel_identified", person_key)
    else
      _ -> conn
    end
  end

  # Returns `{conn, value, :new | :existing}` — callers need to know whether this request
  # is the one that established the value.
  defp ensure_cookie(conn, name, generator, valid? \\ fn _ -> true end) do
    case conn.cookies[name] do
      value when is_binary(value) ->
        if valid?.(value), do: {conn, value, :existing}, else: put_new(conn, name, generator)

      _ ->
        put_new(conn, name, generator)
    end
  end

  defp put_new(conn, name, generator) do
    value = generator.()
    conn = put_resp_cookie(conn, name, value, max_age: @max_age, same_site: "Lax")
    {conn, value, :new}
  end
end
