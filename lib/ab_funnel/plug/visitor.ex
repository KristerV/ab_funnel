defmodule AbFunnel.Plug.Visitor do
  @moduledoc """
  Assigns every browser a visitor id and a bucket in each running experiment, both sticky
  for a year, and records where they came from.

  Also binds the browser to whoever is signed in, so apps never have to remember to. Put
  this *after* whatever loads the current user, or that binding has nothing to work with.

  What ends up in `assigns` (and the session, for LiveView to pick up):

    * `:ab_funnel_visitor_id` — `nil` for a bot, which is what makes `track/2` a no-op.
    * `:ab_funnel_assignments` — `%{"deck" => "features"}`, every running experiment.
    * `:ab_funnel_variant` — the first experiment's, for single-experiment apps and for
      templates written before experiments existed.
    * `:ab_funnel_source`, `:ab_funnel_bot`.
  """
  import Plug.Conn

  alias AbFunnel.Assignment
  alias AbFunnel.Experiments

  @max_age 365 * 24 * 60 * 60

  # UTM values are arbitrary strings from the query string, and they end up in event
  # names. Cap and scrub them so a crafted link cannot write whatever it likes into the
  # events table.
  @max_source_length 48

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> fetch_cookies() |> fetch_query_params()

    if AbFunnel.Bot.bot?(conn), do: crawler(conn), else: visitor(conn)
  end

  # A crawler still has to render something, so it gets the control arm of every
  # experiment — but no cookies, no visitor id, and therefore no events. Everything about
  # it is decided per request and forgotten.
  defp crawler(conn) do
    assignments =
      Map.new(Experiments.active(), fn experiment ->
        control = AbFunnel.Experiment.control(experiment)
        {experiment.key, control && control.key}
      end)

    conn
    |> assign(:ab_funnel_bot, true)
    |> assign(:ab_funnel_visitor_id, nil)
    |> assign(:ab_funnel_assignments, assignments)
    |> assign(:ab_funnel_variant, primary_variant(assignments))
    |> assign(:ab_funnel_source, "direct")
  end

  defp visitor(conn) do
    {conn, visitor_id, _} =
      ensure_cookie(conn, "ab_funnel_visitor_id", fn _conn -> Ecto.UUID.generate() end)

    {conn, qa} = qa_override(conn)
    {conn, assignments} = assignments(conn, visitor_id, qa)
    {conn, source, source_state} = ensure_cookie(conn, "ab_funnel_source", &derive_source(&1))

    # Only on the request that established it. Firing whenever the cookie merely *exists*
    # writes a duplicate row on every subsequent page view, forever.
    if source_state == :new and source != "direct" do
      AbFunnel.track(visitor_id, "source:#{source}", assignments)
    end

    conn
    |> put_session("ab_funnel_visitor_id", visitor_id)
    |> put_session("ab_funnel_assignments", assignments)
    |> put_session("ab_funnel_source", source)
    # Assigned as well as put in the session, so `AbFunnel.track(conn, ...)` reads them
    # from the same place it does on a socket.
    |> assign(:ab_funnel_bot, false)
    |> assign(:ab_funnel_visitor_id, visitor_id)
    |> assign(:ab_funnel_assignments, assignments)
    |> assign(:ab_funnel_variant, primary_variant(assignments))
    |> assign(:ab_funnel_source, source)
    |> maybe_identify(visitor_id)
  end

  # One cookie for every experiment rather than one each: adding a test should cost bytes,
  # not another `Set-Cookie` on every response. Rewritten only when something new was
  # actually assigned.
  defp assignments(conn, visitor_id, qa) do
    stored =
      conn.cookies["ab_funnel_assignments"]
      |> Assignment.decode()
      |> seed_from_legacy_cookie(conn)

    {assignments, state} = Assignment.resolve(visitor_id, stored)

    conn =
      if state == :changed do
        put_cookie(conn, "ab_funnel_assignments", Assignment.encode(assignments))
      else
        conn
      end

    {conn, merge_qa(assignments, qa)}
  end

  # An install that predates experiments has a single `ab_funnel_variant` cookie. Reading
  # it once, into whichever experiment declares that variant, is what stops everyone
  # already mid-test from being rebucketed the moment the library is upgraded.
  defp seed_from_legacy_cookie(stored, conn) do
    with variant when is_binary(variant) <- conn.cookies["ab_funnel_variant"],
         experiment when not is_nil(experiment) <- Experiments.owning(variant) do
      Map.put_new(stored, experiment.key, variant)
    else
      _ -> stored
    end
  end

  # `?ab_funnel=deck:features` forces a bucket so a developer can look at the other arm;
  # `?ab_funnel=off` clears it. Both are validated against what the app declares, so this
  # is not a way to write arbitrary variants into the table.
  #
  # Anyone using it is marked, and the report drops them. Without that this would be a hole
  # straight through the experiment: the person most likely to force a bucket is the one
  # who then reads the numbers.
  defp qa_override(conn) do
    stored = conn.cookies["ab_funnel_qa"] |> Assignment.decode() |> Assignment.validate()

    case conn.query_params["ab_funnel"] do
      nil ->
        {conn, stored}

      "off" ->
        {put_resp_cookie(conn, "ab_funnel_qa", "", max_age: 0, same_site: "Lax"), %{}}

      requested ->
        case requested |> Assignment.decode() |> Assignment.validate() do
          empty when empty == %{} -> {conn, stored}
          forced -> {put_cookie(conn, "ab_funnel_qa", Assignment.encode(forced)), forced}
        end
    end
  end

  defp merge_qa(assignments, qa) when qa == %{}, do: assignments

  defp merge_qa(assignments, qa) do
    assignments |> Map.merge(qa) |> Map.put(Assignment.qa_key(), "1")
  end

  # Templates written against `@ab_funnel_variant` predate experiments and belong to apps
  # running exactly one, so the first declared experiment is the only sensible answer.
  defp primary_variant(assignments) do
    case Experiments.active() do
      [first | _] -> Map.get(assignments, first.key)
      [] -> nil
    end
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
  defp ensure_cookie(conn, name, generator) do
    case conn.cookies[name] do
      value when is_binary(value) and value != "" ->
        {conn, value, :existing}

      _ ->
        value = generator.(conn)
        {put_cookie(conn, name, value), value, :new}
    end
  end

  defp put_cookie(conn, name, value) do
    put_resp_cookie(conn, name, value, max_age: @max_age, same_site: "Lax")
  end
end
