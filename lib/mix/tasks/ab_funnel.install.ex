if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AbFunnel.Install do
    use Igniter.Mix.Task

    @shortdoc "Installs AbFunnel into your Phoenix app"

    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      app_module = app_name |> Atom.to_string() |> Macro.camelize() |> String.to_atom()
      variants_module = Module.concat(app_module, ABVariants)
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
        [:variants],
        {:code, Sourceror.parse_string!("#{inspect(variants_module)}")}
      )
      |> Igniter.create_new_file(
        "lib/#{app_name}/ab_variants.ex",
        """
        defmodule #{inspect(variants_module)} do
          use AbFunnel.Variants

          def variants do
            [
              %{key: :control, label: "Control", active: true},
              %{key: :treatment, label: "Treatment", active: true}
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

      2. Add the plug to your router's :browser pipeline:
         plug AbFunnel.Plug.Visitor

      3. Mount the admin dashboard in your router:
         live "/admin/ab_funnel", AbFunnel.AdminLive

      4. Attach the LiveView hook — either globally in your router:
           live_session :default, on_mount: [AbFunnel.LiveView] do
             # your live routes
           end

         Or per-LiveView:
           on_mount AbFunnel.LiveView

      5. Track events in your LiveViews:
         AbFunnel.track(socket, "landed")
         AbFunnel.track(socket, "signup", %{plan: "pro"})
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
