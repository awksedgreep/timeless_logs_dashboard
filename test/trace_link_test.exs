defmodule TimelessLogsDashboard.TraceLinkTest do
  @moduledoc """
  A log entry carrying a trace id links to the trace lookup page.

  The link is built in entry_row from the routing context — page, socket and
  the traces page name. Without all three it silently falls back to rendering
  the id as plain text, which is what the live tail did: it passed only the
  entry, so tail entries showed a trace id that could not be clicked while the
  identical entry in search results could.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  # live_dashboard_path/5 resolves through the router, so the link cannot be
  # exercised without one.
  defmodule Router do
    use Phoenix.Router
    import Phoenix.LiveDashboard.Router

    scope "/" do
      live_dashboard("/dashboard",
        additional_pages: [
          logs: TimelessLogsDashboard.Page,
          traces: TimelessTracesDashboard.Page
        ]
      )
    end
  end

  # Only what path building touches.
  defmodule Endpoint do
    def path(path), do: path
    def script_name, do: []
    def config(:render_errors), do: []
    def config(_), do: nil
  end

  defp socket, do: %Phoenix.LiveView.Socket{router: Router, endpoint: Endpoint}

  alias Phoenix.LiveDashboard.PageBuilder
  alias TimelessLogsDashboard.Components

  @trace_id "3154f7058d8c04fbe520b3e0c628ff85"

  defp entry do
    %{
      timestamp: 1_700_000_000_000_000,
      level: :info,
      message: "GET /dashboard",
      metadata: %{"trace_id" => @trace_id, "service" => "api"}
    }
  end

  defp page, do: %PageBuilder{params: %{}, route: :logs, node: node()}

  test "search results link the trace id" do
    html =
      render_component(&Components.search_tab/1, %{
        entries: [entry()],
        total: 1,
        search: "",
        level: "",
        window: "24h",
        windows: TimelessLogsDashboard.Page.window_options(),
        current_page: 1,
        per_page: 25,
        has_more: false,
        page: page(),
        socket: socket(),
        traces_page: :traces
      })

    assert html =~ "<a", "the trace id should be a link"
    assert html =~ "trace_id=#{@trace_id}" or html =~ "nav=traces"
  end

  test "live tail links the trace id too" do
    html =
      render_component(&Components.tail_tab/1, %{
        entries: [entry()],
        subscribed: true,
        error: nil,
        page: page(),
        socket: socket(),
        traces_page: :traces
      })

    assert html =~ "nav=traces",
           "a tail entry's trace id must link to the trace lookup, not render as text"
  end

  test "without routing context the id still renders, just unlinked" do
    html =
      render_component(&Components.tail_tab/1, %{
        entries: [entry()],
        subscribed: true,
        error: nil
      })

    assert html =~ @trace_id, "the id must still be visible"
    refute html =~ "nav=traces"
  end
end
