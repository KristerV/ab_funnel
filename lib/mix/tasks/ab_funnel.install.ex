if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AbFunnel.Install do
    use Igniter.Mix.Task

    @shortdoc "Installs AbFunnel into your Phoenix app"

    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      app_module = app_name |> Atom.to_string() |> Macro.camelize() |> String.to_atom()
      experiments_module = Module.concat(app_module, ABTests)
      repo_module = Module.concat(app_module, Repo)

      igniter
      |> Igniter.Project.Config.configure(
        "config.exs",
        :ab_funnel,
        [:repo],
        {:code, Sourceror.parse_string!("#{inspect(repo_module)}")}
      )
      |> Igniter.Project.Config.configure(
        "config.exs",
        :ab_funnel,
        [:experiments],
        {:code, Sourceror.parse_string!("#{inspect(experiments_module)}")}
      )
      |> Igniter.create_new_file(
        "lib/#{app_name}/ab_tests.ex",
        """
        defmodule #{inspect(experiments_module)} do
          use AbFunnel.Experiments

          def experiments do
            [
              %{
                key: :onboarding,
                variants: [:control, :treatment],
                # The funnel, in order. The first step is the entry event: only people who
                # fire it are in the experiment at all. The last is the goal, which is what
                # significance is measured on.
                #
                # Declaring it is optional — leave `steps` out and the order is inferred
                # from the data, which works for a single linear journey and not much else.
                steps: ~w(signed_up completed_profile activated)
              }
            ]
          end
        end
        """
      )
      |> Igniter.Libs.Ecto.gen_migration(repo_module, "create_ab_funnel_events",
        body: """
        def up, do: AbFunnel.Migrations.up()
        def down, do: AbFunnel.Migrations.down()
        """
      )
      |> Igniter.add_notice("""
      AbFunnel installed! Next steps:

      1. Run migrations:
         mix ecto.migrate

      2. Add the plug to your router's :browser pipeline, AFTER whatever loads the
         current user (that is what lets it join a person's devices automatically):
           plug AbFunnel.Plug.Visitor

      3. Attach the LiveView hook, again after whatever assigns the current user:
           live_session :default,
             on_mount: [{MyAppWeb.UserAuth, :mount_current_user}, AbFunnel.LiveView] do
             # your live routes
           end

         Or per-LiveView:
           on_mount AbFunnel.LiveView

      4. Mount the dashboard behind your own auth:
           live "/admin/ab_funnel", AbFunnel.AdminLive

      5. Track the steps you declared in #{inspect(experiments_module)}:
           AbFunnel.track(socket, "signed_up")
           AbFunnel.track(conn, "activated", %{plan: "pro"})

      6. Branch on the variant:
           if AbFunnel.variant(socket, :onboarding) == "treatment" do
      """)
    end
  end
else
  defmodule Mix.Tasks.AbFunnel.Install do
    use Mix.Task

    @shortdoc "Installs AbFunnel into your Phoenix app | Requires igniter"

    def run(_argv) do
      Mix.shell().error("""
      The task 'ab_funnel.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
