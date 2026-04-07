defmodule TimelessLogsDashboardTest do
  use ExUnit.Case

  alias Phoenix.LiveDashboard.NavBarComponent
  alias Phoenix.LiveDashboard.PageBuilder

  test "page module implements PageBuilder callbacks" do
    Code.ensure_loaded!(TimelessLogsDashboard.Page)
    assert function_exported?(TimelessLogsDashboard.Page, :menu_link, 2)
    assert function_exported?(TimelessLogsDashboard.Page, :render, 1)
    assert function_exported?(TimelessLogsDashboard.Page, :mount, 3)
    assert function_exported?(TimelessLogsDashboard.Page, :handle_params, 3)
    assert function_exported?(TimelessLogsDashboard.Page, :handle_event, 3)
    assert function_exported?(TimelessLogsDashboard.Page, :handle_info, 2)
  end

  test "menu_link returns ok with TimelessLogs label" do
    assert {:ok, "TimelessLogs"} = TimelessLogsDashboard.Page.menu_link(%{}, %{})
  end

  test "stats tab is active by default when nav param is missing" do
    assigns = %{
      page: %PageBuilder{params: %{}, route: :logs, node: nil},
      item: [
        %{name: "stats", label: "Stats"},
        %{name: "search", label: "Search"},
        %{name: "tail", label: "Live Tail"}
      ]
    }

    normalized = NavBarComponent.normalize_assigns(assigns)

    assert normalized.current.name == "stats"
  end

  test "explicit nav param still selects the requested tab" do
    assigns = %{
      page: %PageBuilder{params: %{"nav" => "search"}, route: :logs, node: nil},
      item: [
        %{name: "stats", label: "Stats"},
        %{name: "search", label: "Search"},
        %{name: "tail", label: "Live Tail"}
      ]
    }

    normalized = NavBarComponent.normalize_assigns(assigns)

    assert normalized.current.name == "search"
  end
end
