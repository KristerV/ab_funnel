defmodule AbFunnel.AdminLiveTest do
  @moduledoc """
  The dashboard renders whatever the report hands it, including the awkward states — no
  experiments, no goal, an arm with nobody in it, a step nobody reached. Every one of those
  is a division by zero waiting to happen, and they all show up on day one of an install.
  """
  use AbFunnel.DataCase, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  defp html(report) do
    %{report: report, __changed__: nil}
    |> AbFunnel.AdminLive.render()
    |> rendered_to_string()
  end

  test "mounting builds the report, and refreshing rebuilds it" do
    # `render/1` is exercised below against a report built by hand; this is the only test
    # that the LiveView actually wires itself to the report at all.
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

    assert {:ok, mounted} = AbFunnel.AdminLive.mount(%{}, %{}, socket)
    assert Enum.map(mounted.assigns.report.experiments, & &1.key) == ["deck", "flow", "pricing"]

    journey("a", ~w(deck_started slide_f_intro), %{"deck" => "features"})

    assert {:noreply, refreshed} = AbFunnel.AdminLive.handle_event("refresh", %{}, mounted)
    assert experiment(refreshed.assigns.report, "deck").exposed == 1
  end

  test "an install with no data yet renders the declared funnel, all zeroes" do
    # The most useful thing a fresh dashboard can do is show the funnel it is *about* to
    # measure, so a mistyped event name is obvious before any data arrives.
    page = html(report())

    assert page =~ "Demo deck"
    assert page =~ "Nothing to measure yet"
    assert page =~ "Deck started (entry)"
    assert page =~ "Lead submitted"
  end

  test "a funnel with a step nobody reached renders it as zero" do
    journey("a", ~w(deck_started slide_f_intro), %{"deck" => "features"})

    page = html(report())

    assert page =~ "Deck started (entry)"
    assert page =~ "Slide cta"
    assert page =~ "abf-card zero"
  end

  test "a small experiment is reported as collecting, never as a result" do
    journey("a", ~w(deck_started lead_submitted), %{"deck" => "features"})
    journey("b", ~w(deck_started), %{"deck" => "solving_emails"}, 10)

    page = html(report())

    assert page =~ "Collecting"
    refute page =~ "wins"
  end

  test "an experiment with no experiments configured at all is explained, not blank" do
    page = html(%{report() | experiments: []})

    assert page =~ "No experiments are running"
    assert page =~ "config :ab_funnel"
  end
end
