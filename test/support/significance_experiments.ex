defmodule AbFunnel.SignificanceExperiments do
  @moduledoc """
  Two experiments sized so a test can actually reach a verdict.

  `signup` declares `mde: 1.0` — "only tell me about a doubling" — which needs about two
  hundred people per arm rather than the several thousand a realistic 20% lift takes. The
  arithmetic is identical; only the number of rows a test has to write changes.
  """
  use AbFunnel.Experiments

  def experiments do
    [
      %{
        key: :signup,
        variants: [:a, :b],
        entry: "signup_started",
        goal: "signup_done",
        mde: 1.0
      },
      %{
        key: :split,
        variants: [heavy: 90, light: 10],
        goal: "converted"
      },
      %{
        key: :three,
        variants: [:a, :b, :c],
        goal: "converted",
        mde: 1.0
      }
    ]
  end
end
