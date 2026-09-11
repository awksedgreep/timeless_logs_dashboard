defmodule TimelessLogsDashboard.RouterTest do
  use ExUnit.Case, async: true

  alias TimelessLogsDashboard.Router

  defmodule MountedRouter do
    use Phoenix.Router
    import TimelessLogsDashboard.Router

    scope "/" do
      timeless_logs_dashboard("/dashboard")
    end
  end

  test "the macro mounts a consumer router" do
    assert length(MountedRouter.__routes__()) == 5
  end

  test "uses a namespaced live session by default" do
    assert Router.dashboard_options([])[:live_session_name] == :timeless_logs_dashboard
  end

  test "allows the live session name to be overridden" do
    options = Router.dashboard_options(live_dashboard: [live_session_name: :admin_dashboard])

    assert options[:live_session_name] == :admin_dashboard
  end

  test "merges consumer pages and options with the logs page" do
    options =
      Router.dashboard_options(
        live_dashboard: [metrics: ExampleMetrics, additional_pages: [traces: ExampleTraces]]
      )

    assert options[:metrics] == ExampleMetrics
    assert options[:additional_pages][:traces] == ExampleTraces
    assert options[:additional_pages][:logs] == TimelessLogsDashboard.Page
  end
end
