defmodule Mix.Tasks.AbFunnel.Gen.Migration do
  use Mix.Task

  import Mix.Ecto
  import Mix.Generator

  @shortdoc "Generates the AbFunnel database migration"

  def run(args) do
    repos = parse_repo(args)

    Enum.each(repos, fn repo ->
      path = Ecto.Migrator.migrations_path(repo)
      File.mkdir_p!(path)

      timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
      file = Path.join(path, "#{timestamp}_create_ab_funnel_events.exs")

      repo_module = inspect(repo)

      content = """
      defmodule #{repo_module}.Migrations.CreateAbFunnelEvents do
        use Ecto.Migration

        def up, do: AbFunnel.Migrations.up()
        def down, do: AbFunnel.Migrations.down()
      end
      """

      create_file(file, content)
    end)
  end
end
