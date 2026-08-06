defmodule AbFunnel.Bot do
  @moduledoc """
  Whether a request came from something that cannot convert.

  Crawlers, uptime checks and link-preview fetchers all land on the page, get bucketed, and
  fire whatever the top of the funnel tracks. They never reach the bottom. The effect is a
  first step inflated by traffic that was never going to convert, which drags every rate
  down and — because bots do not spread evenly across arms — adds noise exactly where the
  comparison is being made.

  Deliberately a user-agent substring list rather than anything cleverer. It catches the
  overwhelming majority by volume, costs a regex per request, and has no false positive
  worse than "one real visitor was not counted".
  """

  @pattern ~r/bot\b|bot[\/_-]|spider|crawl|slurp|scrape|headless|phantomjs|puppeteer|playwright|selenium|lighthouse|pagespeed|pingdom|uptime|monitoring|curl\/|wget|python-requests|go-http-client|okhttp|java\/|libwww|httpclient|facebookexternalhit|whatsapp|telegrambot|discordbot|slackbot|twitterbot|linkedinbot|embedly|quora link preview|redditbot|applebot|bingpreview|yandex|baiduspider|duckduckbot|semrush|ahrefs|mj12|dotbot|petalbot|gptbot|oai-searchbot|chatgpt-user|claudebot|claude-web|anthropic-ai|perplexitybot|ccbot|bytespider|amazonbot|google-extended/i

  @doc "Whether this conn looks automated. A missing user agent is not enough to say so."
  def bot?(%Plug.Conn{} = conn) do
    conn
    |> Plug.Conn.get_req_header("user-agent")
    |> List.first()
    |> bot?()
  end

  def bot?(nil), do: false
  def bot?(""), do: false
  def bot?(user_agent) when is_binary(user_agent), do: Regex.match?(@pattern, user_agent)
  def bot?(_), do: false
end
