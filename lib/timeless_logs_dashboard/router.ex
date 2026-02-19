defmodule TimelessLogsDashboard.Router do
  @moduledoc """
  Router macro for one-line LiveDashboard setup with TimelessLogs pages.

  ## Usage

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import TimelessLogsDashboard.Router

        scope "/" do
          pipe_through :browser
          timeless_logs_dashboard "/dashboard"
        end
      end

  ## Options

    * `:live_dashboard` — extra opts merged into `live_dashboard` call
  """

  @doc """
  Mounts LiveDashboard with the TimelessLogs page.
  """
  defmacro timeless_logs_dashboard(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      import Phoenix.LiveDashboard.Router

      extra = Keyword.get(opts, :live_dashboard, [])

      dashboard_opts =
        [
          live_session_name: :timeless_logs_dashboard,
          additional_pages: [logs: TimelessLogsDashboard.Page]
        ] ++ extra

      live_dashboard path, dashboard_opts
    end
  end
end
