defmodule AbFunnel.Context do
  @moduledoc """
  Pulls the visitor, their assignments and the current user out of whatever the caller is
  holding.

  A `Plug.Conn` and a `Phoenix.LiveView.Socket` both carry `assigns`, and both the plug and
  the `on_mount` hook put the same keys there — so one clause covers controllers and
  LiveViews alike, and callers never have to know which they have.
  """

  @doc "The `{visitor_id, assignments}` for this request or socket, or `{nil, %{}}`."
  def visitor(%{assigns: assigns}) do
    {assigns[:ab_funnel_visitor_id], assigns[:ab_funnel_assignments] || %{}}
  end

  def visitor(_), do: {nil, %{}}

  @doc """
  The variant this visitor is in for one experiment, or `nil`.

  With no argument, the first running experiment's — which is the only one there is in an
  app that has not declared more.
  """
  def variant(conn_or_socket, experiment \\ nil)

  def variant(conn_or_socket, nil) do
    case AbFunnel.Experiments.active() do
      [first | _] -> variant(conn_or_socket, first.key)
      [] -> nil
    end
  end

  def variant(conn_or_socket, experiment) do
    {_visitor, assignments} = visitor(conn_or_socket)
    Map.get(assignments, to_string(experiment))
  end

  @doc """
  The signed-in user, under whichever assign the host app uses.

  Defaults to `:current_user`, which is the Phoenix convention; override with
  `config :ab_funnel, current_user_assign: :current_admin`.
  """
  def current_user(%{assigns: assigns}) do
    assigns[Application.get_env(:ab_funnel, :current_user_assign, :current_user)]
  end

  def current_user(_), do: nil
end
