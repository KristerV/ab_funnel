defmodule AbFunnel.BotTest do
  @moduledoc """
  Bots land on the page, get bucketed, and fire whatever the top of the funnel tracks.
  They never reach the bottom. Left in, they inflate the first step with traffic that was
  never going to convert.
  """
  use ExUnit.Case, async: true

  alias AbFunnel.Bot

  @bots [
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
    "Mozilla/5.0 (compatible; AhrefsBot/7.0; +http://ahrefs.com/robot/)",
    "facebookexternalhit/1.1",
    "Slackbot-LinkExpanding 1.0",
    "WhatsApp/2.23",
    "Mozilla/5.0 (X11; Linux x86_64) HeadlessChrome/120.0.0.0",
    "curl/8.4.0",
    "python-requests/2.31.0",
    "Mozilla/5.0 (compatible; ClaudeBot/1.0)",
    "Mozilla/5.0 (compatible; GPTBot/1.0)"
  ]

  @humans [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0"
  ]

  test "catches the crawlers, previewers and scripts" do
    for agent <- @bots, do: assert(Bot.bot?(agent), "expected a bot: #{agent}")
  end

  test "leaves real browsers alone" do
    for agent <- @humans, do: refute(Bot.bot?(agent), "expected a human: #{agent}")
  end

  test "a missing user agent is not evidence of anything" do
    # Plenty of legitimate requests arrive without one, and treating them as bots would
    # silently drop real visitors.
    assert Bot.bot?(nil) == false
    assert Bot.bot?("") == false
  end
end
