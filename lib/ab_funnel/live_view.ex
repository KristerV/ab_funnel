defmodule AbFunnel.LiveView do
  @moduledoc """
  Lifts the visitor, their assignments and the source out of the session into
  `socket.assigns`, so `AbFunnel.track(socket, ...)` works and templates can branch on
  `@ab_funnel_variant` or `AbFunnel.variant(@socket, :pricing)`.

  List it after whatever assigns the current user, so it can bind the browser to them:

      live_session :default,
        on_mount: [{MyAppWeb.UserAuth, :mount_current_user}, AbFunnel.LiveView] do
  """
  import Phoenix.Component, only: [assign: 3]

  alias AbFunnel.Experiments

  def on_mount(:default, _params, session, socket) do
    assignments = session["ab_funnel_assignments"] || %{}

    socket =
      socket
      |> assign(:ab_funnel_visitor_id, session["ab_funnel_visitor_id"])
      |> assign(:ab_funnel_assignments, assignments)
      |> assign(:ab_funnel_variant, primary_variant(assignments))
      |> assign(:ab_funnel_source, session["ab_funnel_source"])

    maybe_identify(socket, session)

    {:cont, socket}
  end

  defp primary_variant(assignments) do
    case Experiments.active() do
      [first | _] -> Map.get(assignments, first.key)
      [] -> nil
    end
  end

  # The plug has usually bound this browser already and left a marker in the session, so
  # this is the uncommon path: a mount reached without a fresh request through the
  # pipeline. Unlike the plug we cannot write the session back, so the check is against
  # whatever the last real request left there.
  defp maybe_identify(socket, session) do
    with user when not is_nil(user) <- AbFunnel.Context.current_user(socket),
         person_key when is_binary(person_key) <- AbFunnel.person_key_for(user),
         true <- session["ab_funnel_identified"] != person_key do
      AbFunnel.identify(socket, person_key)
    end
  end
end
