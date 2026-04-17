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

    4. Track events in your LiveViews:
       visitor_id = session["ab_funnel_visitor_id"]
       variant = session["ab_funnel_variant"]
       AbFunnel.track(visitor_id, "landed", variant)
    """)
  end
end
