defmodule AbFunnel do
  def track(%Phoenix.LiveView.Socket{} = socket, event), do: track(socket, event, %{})

  def track(%Phoenix.LiveView.Socket{assigns: assigns}, event, metadata)
      when is_binary(event) and is_map(metadata) do
    AbFunnel.Events.track(
      assigns.ab_funnel_visitor_id,
      event,
      assigns.ab_funnel_variant,
      metadata
    )
  end

  def track(visitor_id, event, variant) when is_binary(visitor_id) do
    AbFunnel.Events.track(visitor_id, event, variant, %{})
  end

  def track(visitor_id, event, variant, metadata) when is_binary(visitor_id) do
    AbFunnel.Events.track(visitor_id, event, variant, metadata)
  end

  def repo do
    Application.fetch_env!(:ab_funnel, :repo)
  end

  def variants_module do
    Application.fetch_env!(:ab_funnel, :variants)
  end
end
