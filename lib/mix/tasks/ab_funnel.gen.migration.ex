defmodule Mix.Tasks.AbFunnel.Gen.Migration do
  use Mix.Task

  import Mix.Ecto
  import Mix.EctoSQL
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
      # `parse_repo/1` reads a module *name* out of config and nothing more, so without
      # this the first call into the repo raises `Repo.config/0 is undefined` on any app
      # whose code has not already been loaded — which is every app running this task
      # straight from a shell, the way the README says to.
      ensure_repo(repo, args)

      # `source_repo_priv/1`, not `Ecto.Migrator.migrations_path/1`: the latter resolves
      # through `Application.app_dir/2` into `_build`. Mix symlinks `_build/…/priv` back
      # to the source tree for the project being built, so it happens to land in the right
      # place there and nowhere else — a repo that lives in a dependency would have its
      # migration written into a build artifact and silently lost on `mix clean`.
      path = Path.join(source_repo_priv(repo), "migrations")
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
