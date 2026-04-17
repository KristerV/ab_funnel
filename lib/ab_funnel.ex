defmodule AbFunnel do
  def track(visitor_id, event, variant, metadata \\ %{}) do
    AbFunnel.Events.track(visitor_id, event, variant, metadata)
  end

  def repo do
    Application.fetch_env!(:ab_funnel, :repo)
  end

  def variants_module do
    Application.fetch_env!(:ab_funnel, :variants)
  end
end
