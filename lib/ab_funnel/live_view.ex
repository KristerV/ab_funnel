defmodule AbFunnel.LiveView do
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign(:ab_funnel_visitor_id, session["ab_funnel_visitor_id"])
      |> assign(:ab_funnel_variant, session["ab_funnel_variant"])
      |> assign(:ab_funnel_source, session["ab_funnel_source"])

    {:cont, socket}
  end
end
