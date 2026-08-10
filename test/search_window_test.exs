defmodule TimelessLogsDashboard.SearchWindowTest do
  @moduledoc """
  The search form bounds queries by time unless asked not to.

  A message search has no pushdown in the libSQL engine — `:message` also
  matches metadata values and the engine can only match the message, so the
  store returns rows and the shared filter applies the term. Unbounded, that
  decodes the whole store: roughly 0.8s per 200k entries when measured, which
  is several seconds against a real one, on every submit.

  Timestamp bounds do push down, so the default range is what keeps the common
  case cheap. These tests assert the bound actually reaches the query, and that
  "All time" still escapes it.
  """

  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Phoenix.LiveDashboard.PageBuilder
  alias TimelessLogsDashboard.Page

  defmodule Recorder do
    @moduledoc false
    @behaviour TimelessLogsDashboard.HistoricalSource

    @impl true
    def query(filters, _opts) do
      send(self(), {:query_filters, filters})
      {:ok, %{entries: [], total: 0, has_more: false}}
    end

    @impl true
    def stats(_opts), do: {:ok, %{}}

    @impl true
    def subscribe(_opts), do: :ok

    @impl true
    def unsubscribe(_opts), do: :ok
  end

  setup do
    previous = Application.get_env(:timeless_logs_dashboard, :historical_source)
    Application.put_env(:timeless_logs_dashboard, :historical_source, Recorder)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:timeless_logs_dashboard, :historical_source, previous),
        else: Application.delete_env(:timeless_logs_dashboard, :historical_source)
    end)

    :ok
  end

  defp search(params) do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        page: %PageBuilder{params: params, route: :logs, node: nil},
        per_page: 25
      }
    }

    Page.handle_params(Map.put(params, "nav", "search"), "/", socket)

    receive do
      {:query_filters, filters} -> filters
    after
      0 -> flunk("the page never queried the historical source")
    end
  end

  test "a search with no explicit range is bounded to the last 24 hours" do
    filters = search(%{"search" => "boom"})

    assert {:message, "boom"} in filters
    assert since = Keyword.get(filters, :since)

    day_ago =
      DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.to_unix(:microsecond)

    # Within a minute of 24h ago, allowing for clock drift during the test.
    assert_in_delta since, day_ago, 60_000_000
  end

  test "a narrower range is respected" do
    filters = search(%{"search" => "boom", "window" => "1h"})

    assert since = Keyword.get(filters, :since)

    hour_ago =
      DateTime.utc_now() |> DateTime.add(-3_600, :second) |> DateTime.to_unix(:microsecond)

    assert_in_delta since, hour_ago, 60_000_000
  end

  test "All time removes the bound entirely" do
    filters = search(%{"search" => "boom", "window" => "all"})

    refute Keyword.has_key?(filters, :since)
    assert {:message, "boom"} in filters
  end

  test "an explicit since wins over the range" do
    filters = search(%{"search" => "boom", "since" => "1700000000000000"})

    assert Keyword.get(filters, :since) == 1_700_000_000_000_000
  end

  test "an unknown range falls back to the default rather than dropping the bound" do
    filters = search(%{"search" => "boom", "window" => "nonsense"})

    assert since = Keyword.get(filters, :since)

    day_ago =
      DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.to_unix(:microsecond)

    assert_in_delta since, day_ago, 60_000_000
  end

  describe "the pager carries the range" do
    # handle_params honouring an explicit window only proves the page reads it.
    # The pager builds its own links and originally omitted the range, so paging
    # a search over "All time" silently returned 24-hour results from page two
    # on, with a total that no longer matched the pager that produced it.
    alias TimelessLogsDashboard.Components

    test "next/prev params keep the selected range" do
      assert %{window: "all", p: "3"} = Components.page_params(3, "boom", "", "all", 25)
    end

    test "a narrower range also survives paging" do
      assert %{window: "7d"} = Components.page_params(2, "boom", "error", "7d", 50)
    end

    test "the rest of the search is preserved alongside it" do
      params = Components.page_params(2, "boom", "error", "7d", 50)

      assert params.search == "boom"
      assert params.level == "error"
      assert params.per_page == "50"
      assert params.nav == "search"
    end
  end

  test "pagination survives the window: page 2 keeps the bound and shifts the offset" do
    filters = search(%{"search" => "boom", "p" => "2", "per_page" => "25"})

    assert Keyword.get(filters, :offset) == 25
    assert Keyword.get(filters, :limit) == 25
    assert Keyword.has_key?(filters, :since)
  end
end
