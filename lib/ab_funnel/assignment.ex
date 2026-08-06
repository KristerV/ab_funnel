defmodule AbFunnel.Assignment do
  @moduledoc """
  Which variant a visitor is in, for every running experiment.

  Assignment is *derived* by hashing the visitor id together with the experiment key, and
  then *stored* in a cookie. Both halves matter:

    * Deriving it from a hash means a visitor's bucket is reproducible from nothing but
      their id — no coordination, no lookup, and a test can assert on it. It also spreads
      each experiment independently, so being in `features` tells you nothing about which
      pricing arm you are in.
    * Storing it means changing the weights, or retiring an arm, does not silently rebucket
      everyone who is already mid-experiment. Re-derived assignment is the classic way an
      A/B tool ends up comparing two populations that swapped halfway through.

  Assignments live in one cookie for all experiments rather than one cookie each, so
  adding a test costs a few bytes rather than another `Set-Cookie`.
  """

  alias AbFunnel.Experiment
  alias AbFunnel.Experiments

  # Marks a visitor who forced their own bucket via `?ab_funnel=`. Kept alongside the real
  # assignments so the events carry it, and the report can drop those people — someone
  # clicking through their own test must not land in the numbers they are about to read.
  @qa_key "$qa"

  @doc "The key that marks a self-assigned (QA) visitor in an assignments map."
  def qa_key, do: @qa_key

  @doc "Whether this assignments map belongs to someone who picked their own bucket."
  def qa?(assignments) when is_map(assignments), do: Map.has_key?(assignments, @qa_key)
  def qa?(_), do: false

  @doc """
  Bucket `visitor_id` into `experiment`.

  Weights are relative, so `[monthly: 90, annual: 10]` and `[monthly: 9, annual: 1]` are
  the same split. Retired arms (weight `0`) are never handed out.
  """
  def assign(%Experiment{} = experiment, visitor_id) when is_binary(visitor_id) do
    case Experiment.assignable(experiment) do
      [] ->
        nil

      pool ->
        total = pool |> Enum.map(& &1.weight) |> Enum.sum()
        pick(pool, bucket(experiment.key, visitor_id) * total)
    end
  end

  @doc """
  A stable number in `[0, 1)` for this visitor and experiment.

  SHA-256 rather than `:erlang.phash2/1`: the bucket has to mean the same thing across
  releases and machines, and a term hash is only promised to be consistent within one.
  """
  def bucket(experiment_key, visitor_id) do
    <<n::unsigned-integer-size(32), _rest::binary>> =
      :crypto.hash(:sha256, experiment_key <> ":" <> visitor_id)

    n / 0x1_0000_0000
  end

  defp pick([variant], _point), do: variant.key

  defp pick([variant | rest], point) do
    if point < variant.weight, do: variant.key, else: pick(rest, point - variant.weight)
  end

  @doc """
  This visitor's assignment for every running experiment.

  Returns `{assignments, :unchanged | :changed}` — the caller only rewrites the cookie
  when something was actually assigned, which is once per visitor per experiment rather
  than on every request.

  `stored` is whatever the cookie held. Anything in it naming an experiment or a variant
  that is not declared is thrown away and reassigned: a cookie is whatever the client says
  it is, and a visitor must not be able to pick their own arm by editing one.
  """
  def resolve(visitor_id, stored) when is_binary(visitor_id) and is_map(stored) do
    Enum.reduce(Experiments.active(), {%{}, :unchanged}, fn experiment, {acc, state} ->
      case Map.get(stored, experiment.key) do
        variant when is_binary(variant) ->
          if Experiment.known?(experiment, variant) do
            {Map.put(acc, experiment.key, variant), state}
          else
            put_assignment(acc, state, experiment, visitor_id)
          end

        _ ->
          put_assignment(acc, state, experiment, visitor_id)
      end
    end)
  end

  # An experiment whose arms have all been retired has nothing to hand out. Leaving the
  # state alone matters: reporting `:changed` would rewrite the cookie on every single
  # request, forever, without ever adding anything to it.
  defp put_assignment(acc, state, experiment, visitor_id) do
    case assign(experiment, visitor_id) do
      nil -> {acc, state}
      variant -> {Map.put(acc, experiment.key, variant), :changed}
    end
  end

  @doc """
  Keep only the pairs naming an experiment that declares that variant.

  Used on anything a client hands us, which is the QA override cookie and the query
  parameter behind it.
  """
  def validate(assignments) when is_map(assignments) do
    declared = Map.new(Experiments.all(), &{&1.key, &1})

    assignments
    |> Enum.filter(fn {key, variant} ->
      case Map.fetch(declared, key) do
        {:ok, experiment} -> Experiment.known?(experiment, variant)
        :error -> false
      end
    end)
    |> Map.new()
  end

  @doc "`%{\"deck\" => \"features\"}` -> `\"deck:features\"`, for the cookie."
  def encode(assignments) when is_map(assignments) do
    assignments
    |> Enum.sort()
    |> Enum.map_join("|", fn {key, variant} -> "#{key}:#{variant}" end)
  end

  @doc "The inverse of `encode/1`, tolerant of anything a client may have put there."
  def decode(nil), do: %{}

  def decode(encoded) when is_binary(encoded) do
    encoded
    |> String.split("|", trim: true)
    |> Enum.flat_map(fn pair ->
      case String.split(pair, ":", parts: 2) do
        [key, variant] when key != "" and variant != "" -> [{key, variant}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  def decode(_), do: %{}
end
