defmodule TimelessLogsDashboardTest do
  use ExUnit.Case

  test "page module implements PageBuilder callbacks" do
    Code.ensure_loaded!(TimelessLogsDashboard.Page)
    assert function_exported?(TimelessLogsDashboard.Page, :menu_link, 2)
    assert function_exported?(TimelessLogsDashboard.Page, :render, 1)
    assert function_exported?(TimelessLogsDashboard.Page, :mount, 3)
    assert function_exported?(TimelessLogsDashboard.Page, :handle_params, 3)
    assert function_exported?(TimelessLogsDashboard.Page, :handle_event, 3)
    assert function_exported?(TimelessLogsDashboard.Page, :handle_info, 2)
  end

  test "menu_link returns ok with Logs label" do
    assert {:ok, "Logs"} = TimelessLogsDashboard.Page.menu_link(%{}, %{})
  end
end
