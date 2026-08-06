defmodule AbFunnel.TestExperiments do
  @moduledoc """
  Three experiments covering the three shapes that behave differently:

    * `deck` — an entry event and a declared, per-variant step list. The gated path.
    * `flow` — nothing declared, so order is inferred and everybody is in the funnel. The
      behaviour an app gets for free, and what the library did before any of this existed.
    * `pricing` — uneven weights, for assignment and sample-ratio checks.
  """
  use AbFunnel.Experiments

  def experiments do
    [
      %{
        key: :deck,
        label: "Demo deck",
        variants: [
          %{key: :features, label: "Features first"},
          %{key: :solving_emails, label: "Solving emails"}
        ],
        entry: "deck_started",
        goal: "lead_submitted",
        steps: {__MODULE__, :deck_steps, 1},
        mde: 0.2
      },
      %{
        key: :flow,
        variants: [:control, :treatment, %{key: :old, label: "Old", active: false}]
      },
      %{
        key: :pricing,
        variants: [monthly: 90, annual: 10]
      }
    ]
  end

  def deck_steps("solving_emails") do
    ~w(deck_started slide_s_intro slide_cta deck_completed lead_submitted)
  end

  def deck_steps(_features) do
    ~w(deck_started slide_f_intro slide_cta deck_completed lead_submitted)
  end
end
