defmodule AbFunnel.Context do
  @moduledoc """
  Pulls the visitor, variant and current user out of whatever the caller is holding.

  A `Plug.Conn` and a `Phoenix.LiveView.Socket` both carry `assigns`, and both the plug
  and the `on_mount` hook put the same three keys there — so one clause covers
  controllers and LiveViews alike, and callers never have to know which they have.
  """

  @doc "The `{visitor_id, variant}` for this request or socket, or `{nil, nil}`."
  def visitor(%{assigns: assigns}) do
    {assigns[:ab_funnel_visitor_id], assigns[:ab_funnel_variant]}
  end

  def visitor(_), do: {nil, nil}

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
