defmodule AbFunnel do
  @moduledoc """
  Funnel tracking and A/B experiments for Phoenix apps.

  Everything here takes either a `Plug.Conn` or a `Phoenix.LiveView.Socket`, so the same
  call works in a controller and in a LiveView.

      AbFunnel.track(socket, "deck_started")
      AbFunnel.track(conn, "checked_out", %{plan: "pro"})

      if AbFunnel.variant(socket, :pricing) == "annual" do

  Experiments are declared in one module (`AbFunnel.Experiments`) and run concurrently: a
  visitor is bucketed once per experiment, so a second test costs a second bucket rather
  than the cross product of both tests' arms.

  Identity is handled for you wherever it can be. Once someone is signed in, the plug and
  the `on_mount` hook bind their browser to them automatically — you only call
  `identify_by_email/2` for the one case nothing can infer, which is someone who has handed
  over an email but does not have an account yet.
  """

  alias AbFunnel.Context
  alias AbFunnel.Services.Events
  alias AbFunnel.Services.Identities

  @doc """
  Record an event against the current visitor, stamped with every bucket they are in.

  Does nothing when there is no visitor — an endpoint outside the browser pipeline, a
  crawler — rather than raising in the middle of whatever the caller was actually doing.
  """
  def track(conn_or_socket, event, metadata \\ %{})

  def track(%Phoenix.LiveView.Socket{} = socket, event, metadata)
      when is_binary(event) and is_map(metadata) do
    # A LiveView mounts twice: once to render the page over HTTP, then again over the
    # socket. Tracking on both writes every event twice. Person counts survive that, but
    # nothing else does — and the second mount is the one where a real browser is
    # definitely present, so it is the one to keep.
    if Phoenix.LiveView.connected?(socket) do
      do_track(socket, event, metadata)
    else
      {:ok, :not_connected}
    end
  end

  def track(%{assigns: _} = conn_or_socket, event, metadata)
      when is_binary(event) and is_map(metadata) do
    do_track(conn_or_socket, event, metadata)
  end

  def track(visitor_id, event, assignments) when is_binary(visitor_id) do
    Events.track(visitor_id, event, assignments, %{})
  end

  def track(visitor_id, event, assignments, metadata) when is_binary(visitor_id) do
    Events.track(visitor_id, event, assignments, metadata)
  end

  defp do_track(conn_or_socket, event, metadata) do
    case Context.visitor(conn_or_socket) do
      {nil, _} -> {:ok, :no_visitor}
      {visitor_id, assignments} -> Events.track(visitor_id, event, assignments, metadata)
    end
  end

  @doc """
  Which arm of `experiment` this visitor is in.

  With no experiment named, the first declared one — the only one there is in an app
  running a single test.

      <.pricing_table annual={AbFunnel.variant(@socket, :pricing) == "annual"} />
  """
  defdelegate variant(conn_or_socket, experiment \\ nil), to: Context

  @doc """
  Bind this browser to a person, so their events join up with whatever else that person
  did on other browsers.

  You rarely need this: anyone signed in is bound automatically. Reach for it when you
  learn who someone is *before* they have an account — typically when they give you an
  email to send a magic link to. Skipping that leaves everything they did beforehand
  attached to nobody, which is the case the whole mechanism exists for.

  Takes any stable opaque string. `identify_by_email/2` derives one the same way the
  automatic binding does, so the two agree.
  """
  def identify(%{assigns: _} = conn_or_socket, person_key) when is_binary(person_key) do
    case Context.visitor(conn_or_socket) do
      {nil, _} -> {:ok, :no_visitor}
      {visitor_id, _} -> Identities.identify(visitor_id, person_key)
    end
  end

  def identify(visitor_id, person_key) when is_binary(visitor_id) and is_binary(person_key) do
    Identities.identify(visitor_id, person_key)
  end

  @doc "Bind this browser to whoever owns `email`."
  def identify_by_email(conn_or_socket, email) when is_binary(email) do
    identify(conn_or_socket, person_key(email))
  end

  @doc """
  A person key derived from an email address.

  Hashed so the table holds no email addresses, and normalised so the address someone
  types into a form matches the one stored on their account later.
  """
  def person_key(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  The person key for a signed-in user, used by the automatic binding.

  Defaults to hashing their `email`, falling back to their `id`. Override for apps keyed
  on something else:

      config :ab_funnel, person_key: {MyApp.Analytics, :person_key, 1}
  """
  def person_key_for(user) do
    case Application.get_env(:ab_funnel, :person_key) do
      {module, function, 1} -> apply(module, function, [user])
      nil -> default_person_key(user)
    end
  end

  defp default_person_key(%{email: email}) when not is_nil(email) do
    # `to_string/1` rather than the raw value: an app may hold a `Ash.CiString` or
    # similar here, and the key has to match the one derived from a typed-in address.
    email |> to_string() |> person_key()
  end

  defp default_person_key(%{id: id}) when not is_nil(id), do: "id:" <> to_string(id)
  defp default_person_key(_), do: nil

  @doc "Every running experiment, measured. See `AbFunnel.Services.Report.run/1`."
  defdelegate report(opts \\ []), to: AbFunnel.Services.Report, as: :run

  def repo do
    Application.fetch_env!(:ab_funnel, :repo)
  end

  @doc """
  The module declaring the experiments.

  Kept under its old name for apps that call it; `AbFunnel.Experiments.module/0` is the
  same thing and reads better next to the rest of that module.
  """
  defdelegate variants_module(), to: AbFunnel.Experiments, as: :module
end
