defmodule AbFunnel.Stats do
  @moduledoc """
  The arithmetic that decides whether a difference between two arms is real.

  A dashboard that shows "12.4% vs 9.1%" and nothing else is worse than no dashboard: it
  reads as a result at any sample size, and four people converting instead of three is not
  a result. Everything here exists to stop that.

  Three questions, in the order they matter:

    1. **Is the split itself broken?** `srm/2` compares the arms' sizes against the weights
       they were meant to get. A 50/50 test that ran 900/1100 has something wrong with it —
       a redirect, a bot, a bug — and no amount of conversion analysis on top is worth
       anything. This is checked first, and it is the check most tools skip.
    2. **How much data does this need?** `sample_size/3` says how many people per arm it
       takes to detect the lift the app declared it cares about. Known up front, so the
       dashboard can show progress instead of a verdict that changes daily.
    3. **Is the difference significant?** `compare/2`, a two-proportion z-test.

  Frequentist and deliberately plain. The one guard against the way this is usually
  misused — refreshing until `p < 0.05` appears — is that `AbFunnel.Services.Report` will
  not call a winner before the sample size from (2) is reached.
  """

  # 95% two-sided, and 80% power. The conventional defaults, and not worth a config key
  # until someone has a reason to move them.
  @z_alpha 1.959964
  @z_power 0.8416212

  @doc """
  Compare a variant against the control.

  Both arms are `{exposed, converted}`. Returns `nil` when either arm is empty, because a
  rate over zero people is not a small number, it is not a number.
  """
  def compare({0, _}, _), do: nil
  def compare(_, {0, _}), do: nil

  def compare({control_n, control_c}, {variant_n, variant_c}) do
    p1 = control_c / control_n
    p2 = variant_c / variant_n

    # Pooled standard error for the test itself: under the null the two arms share one
    # underlying rate, so the best estimate of it uses both arms' data.
    pooled = (control_c + variant_c) / (control_n + variant_n)
    se = :math.sqrt(pooled * (1 - pooled) * (1 / control_n + 1 / variant_n))

    z = if se == 0.0, do: 0.0, else: (p2 - p1) / se

    # Unpooled for the interval, which describes the difference we actually observed
    # rather than the null we are testing against.
    se_diff = :math.sqrt(p1 * (1 - p1) / control_n + p2 * (1 - p2) / variant_n)
    margin = @z_alpha * se_diff

    %{
      z: z,
      p_value: 2 * (1 - normal_cdf(abs(z))),
      # Relative, because "20% better" is how anyone actually talks about a funnel.
      uplift: if(p1 == 0.0, do: nil, else: (p2 - p1) / p1),
      difference: p2 - p1,
      confidence_interval: {p2 - p1 - margin, p2 - p1 + margin}
    }
  end

  @doc """
  People per arm needed to detect a `mde` relative lift on a `baseline` conversion rate.

  `nil` when the baseline is 0 or 1 — there is no lift to size for, and the formula
  divides by zero.
  """
  def sample_size(baseline, mde, arms \\ 2)

  def sample_size(baseline, _mde, _arms) when baseline <= 0 or baseline >= 1, do: nil
  def sample_size(_baseline, mde, _arms) when mde <= 0, do: nil

  def sample_size(baseline, mde, arms) do
    target = min(baseline * (1 + mde), 1.0)
    delta = target - baseline

    if delta <= 0 do
      nil
    else
      mean = (baseline + target) / 2

      n =
        :math.pow(
          @z_alpha * :math.sqrt(2 * mean * (1 - mean)) +
            @z_power *
              :math.sqrt(baseline * (1 - baseline) + target * (1 - target)),
          2
        ) / :math.pow(delta, 2)

      # More arms means more comparisons against the control, so hold the family-wise error
      # rate with a Bonferroni-flavoured bump rather than quietly under-powering the test.
      ceil(n * max(arms - 1, 1))
    end
  end

  @doc """
  Sample ratio mismatch: does the traffic actually split the way it was meant to?

  `observed` is `[{variant, count}]`, `weights` is `[{variant, weight}]`. Returns the
  chi-square p-value, or `nil` when there is not enough to say — fewer than two arms, or
  a total small enough that any split looks plausible.

  A p-value under `0.001` is the usual alarm threshold. It is deliberately far stricter
  than the 0.05 used for the result: this fires on every experiment on every page load, so
  at 0.05 it would cry wolf constantly.
  """
  def srm(observed, weights) do
    total = observed |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    weight_total = weights |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    expected =
      Map.new(weights, fn {variant, weight} -> {variant, total * weight / weight_total} end)

    cond do
      length(observed) < 2 or weight_total <= 0 -> nil
      # Chi-square needs a few expected observations per cell to mean anything.
      total < 100 -> nil
      Enum.any?(expected, fn {_, e} -> e < 5 end) -> nil
      true -> srm_p_value(observed, expected, length(observed) - 1)
    end
  end

  defp srm_p_value(observed, expected, df) do
    chi_square =
      Enum.reduce(observed, 0.0, fn {variant, count}, acc ->
        e = Map.fetch!(expected, variant)
        acc + :math.pow(count - e, 2) / e
      end)

    1 - chi_square_cdf(chi_square, df)
  end

  @doc """
  Upper tail of the standard normal — the probability of seeing `z` or more extreme.
  """
  def normal_cdf(z) do
    0.5 * (1 + erf(z / :math.sqrt(2)))
  end

  @doc """
  Chi-square CDF, via the Wilson–Hilferty cube-root transform to a normal.

  Accurate to about three decimal places for `df >= 1`, which is far beyond what a
  "is this split broken" alarm needs, and saves carrying an incomplete gamma function.
  """
  def chi_square_cdf(x, _df) when x <= 0, do: 0.0

  def chi_square_cdf(x, df) do
    z =
      (:math.pow(x / df, 1 / 3) - (1 - 2 / (9 * df))) /
        :math.sqrt(2 / (9 * df))

    normal_cdf(z)
  end

  @doc """
  Error function, Abramowitz & Stegun 7.1.26.

  Maximum error 1.5e-7 — several orders of magnitude finer than any decision made on it.
  """
  def erf(x) when x < 0, do: -erf(-x)

  def erf(x) do
    t = 1 / (1 + 0.3275911 * x)

    y =
      1 -
        ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t +
           0.254829592) * t * :math.exp(-x * x)

    y
  end
end
