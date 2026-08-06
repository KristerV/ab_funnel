defmodule Mix.Tasks.AbFunnel.Gen.Migration do
  use Mix.Task

  import Mix.Ecto
  import Mix.Generator

  @shortdoc "Generates the AbFunnel database migration"

  @moduledoc """
  Generates the migration for a fresh install:

      mix ab_funnel.gen.migration

  For an app that installed AbFunnel before experiments existed, generate the upgrade
  instead — it adds the `assignments` column and leaves every existing row readable:

      mix ab_funnel.gen.migration --upgrade
  """

  def run(args) do
    {opts, args} = OptionParser.parse!(args, strict: [upgrade: :boolean])
    {name, up, down} = migration(opts[:upgrade])

    args
    |> parse_repo()
    |> Enum.each(fn repo ->
      path = Ecto.Migrator.migrations_path(repo)
      File.mkdir_p!(path)

      timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")

      create_file(Path.join(path, "#{timestamp}_#{name}.exs"), """
      defmodule #{inspect(repo)}.Migrations.#{Macro.camelize(name)} do
        use Ecto.Migration

        def up, do: AbFunnel.Migrations.#{up}
        def down, do: AbFunnel.Migrations.#{down}
      end
      """)
    end)
  end

  defp migration(true) do
    {"add_ab_funnel_event_assignments", "add_event_assignments()", "drop_event_assignments()"}
  end

  defp migration(_) do
    {"create_ab_funnel_events", "up()", "down()"}
  end
end
