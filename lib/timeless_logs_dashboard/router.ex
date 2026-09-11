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

    * `:live_dashboard` — extra opts merged into the `live_dashboard` call.
      Its `:additional_pages` are preserved alongside the logs page, and
      `:live_session_name` can override the default
      `:timeless_logs_dashboard` name.
  """

  @doc """
  Mounts LiveDashboard with the TimelessLogs page.
  """
  defmacro timeless_logs_dashboard(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      import Phoenix.LiveDashboard.Router

      dashboard_opts = TimelessLogsDashboard.Router.dashboard_options(opts)

      live_dashboard(path, dashboard_opts)
    end
  end

  @doc false
  def dashboard_options(opts) do
    extra = Keyword.get(opts, :live_dashboard, [])

    additional_pages =
      extra
      |> Keyword.get(:additional_pages, [])
      |> Keyword.put(:logs, TimelessLogsDashboard.Page)

    extra
    |> Keyword.put_new(:live_session_name, :timeless_logs_dashboard)
    |> Keyword.put(:additional_pages, additional_pages)
  end
end
