defmodule AbFunnel.LifecycleExperiments do
  @moduledoc """
  Experiments in the two states that are not "running normally": one restarted partway
  through, and one switched off.
  """
  use AbFunnel.Experiments

  def experiments do
    [
      %{
        key: :restarted,
        variants: [:a, :b],
        goal: "done",
        since: ~U[2026-08-01 12:05:00.000000Z]
      },
      %{
        key: :finished,
        variants: [:a, :b],
        goal: "done",
        active: false
      }
    ]
  end
end
