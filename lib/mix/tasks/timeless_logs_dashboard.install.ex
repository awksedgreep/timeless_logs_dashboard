if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.TimelessLogsDashboard.Install do
    @shortdoc "Installs TimelessLogsDashboard into your application."
    @moduledoc """
    #{@shortdoc}

    Configures TimelessLogs app environment, sets up your Phoenix router with
    the logs dashboard page, and updates the formatter.

    ## Usage

        mix igniter.install timeless_logs_dashboard
        mix igniter.install timeless_logs_dashboard --storage memory

    ## Options

      * `--storage` — `disk` (default) or `memory`. Memory mode stores logs
        in memory only (lost on restart).

    ## What it does

    1. Adds `config :timeless_logs, data_dir: "priv/timeless_logs"` to `config.exs`
    2. Adds `import TimelessLogsDashboard.Router` to your Phoenix router
    3. Adds `timeless_logs_dashboard "/dashboard"` to your router's browser scope
    4. Adds `:timeless_logs_dashboard` to your `.formatter.exs` import_deps
    5. Reminds you to remove the default LiveDashboard route (avoids live_session conflict)
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :timeless_logs_dashboard,
        schema: [storage: :string],
        defaults: [storage: "disk"],
        required: [],
        positional: [],
        aliases: [],
        composes: [],
        installs: [],
        adds_deps: [],
        example: "mix igniter.install timeless_logs_dashboard --storage memory"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      storage = igniter.args.options[:storage] || "disk"

      igniter
      |> configure_timeless_logs(storage)
      |> setup_router()
      |> Igniter.Project.Formatter.import_dep(:timeless_logs_dashboard)
      |> add_live_dashboard_notice()
    end

    defp configure_timeless_logs(igniter, storage) do
      igniter =
        Igniter.Project.Config.configure(
          igniter,
          "config.exs",
          :timeless_logs,
          [:data_dir],
          "priv/timeless_logs"
        )

      case storage do
        "memory" ->
          Igniter.Project.Config.configure(
            igniter,
            "config.exs",
            :timeless_logs,
            [:storage],
            :memory
          )

        _ ->
          igniter
      end
    end

    defp setup_router(igniter) do
      case Igniter.Libs.Phoenix.select_router(igniter) do
        {igniter, nil} ->
          Igniter.add_warning(igniter, """
          No Phoenix router found. Add the following manually:

              import TimelessLogsDashboard.Router

              scope "/" do
                pipe_through :browser
                timeless_logs_dashboard "/dashboard"
              end
          """)

        {igniter, router} ->
          igniter
          |> add_router_import(router)
          |> Igniter.Libs.Phoenix.append_to_scope(
            "/",
            """
            timeless_logs_dashboard "/dashboard"
            """,
            with_pipelines: [:browser],
            router: router
          )
      end
    end

    defp add_router_import(igniter, router) do
      Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
        case Igniter.Libs.Phoenix.move_to_router_use(igniter, zipper) do
          {:ok, zipper} ->
            {:ok, Igniter.Code.Common.add_code(zipper, "import TimelessLogsDashboard.Router")}

          _ ->
            {:ok, zipper}
        end
      end)
    end

    defp add_live_dashboard_notice(igniter) do
      Igniter.add_notice(igniter, """
      TimelessLogsDashboard installs its own LiveDashboard at /dashboard.

      If your router has a default LiveDashboard route (typically in a
      `if Application.compile_env(:your_app, :dev_routes)` block), you should
      remove it to avoid a live_session conflict.
      """)
    end
  end
else
  defmodule Mix.Tasks.TimelessLogsDashboard.Install do
    @shortdoc "Installs TimelessLogsDashboard (requires igniter)."
    @moduledoc @shortdoc
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'timeless_logs_dashboard.install' requires igniter.
      Please install igniter and try again.

          {:igniter, "~> 0.6", only: [:dev]}

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
