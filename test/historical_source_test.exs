defmodule TimelessLogsDashboard.HistoricalSourceTest do
  use ExUnit.Case, async: false

  alias TimelessLogsDashboard.HistoricalSource

  setup do
    previous = Application.get_env(:timeless_logs_dashboard, :historical_source)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:timeless_logs_dashboard, :historical_source, previous),
        else: Application.delete_env(:timeless_logs_dashboard, :historical_source)
    end)
  end

  test "data-plane source routes reads and rejects live tail without fallback" do
    Application.put_env(
      :timeless_logs_dashboard,
      :historical_source,
      {HistoricalSource.DataPlane, client: __MODULE__.Client}
    )

    assert {:ok, %{entries: [%{message: "kept"}]}} = HistoricalSource.query(level: :info)
    assert {:ok, %{total_entries: 7, storage_mode: :libsql}} = HistoricalSource.stats()
    assert {:error, {:unsupported_capability, :logs_live_tail}} = HistoricalSource.subscribe()
    assert {:error, {:unsupported_capability, :logs_live_tail}} = HistoricalSource.unsubscribe()
  end

  describe "local source honours the subscribe/unsubscribe contract" do
    # TimelessLogs.subscribe/0 delegates to Registry.register/3, which answers
    # {:ok, pid}. Leaking that shape broke live tail: the dashboard matches the
    # declared :ok | {:error, term()} contract and crashed with a
    # CaseClauseError on the success path, so the LiveView died on mount and
    # the page simply hung.
    setup do
      Application.put_env(
        :timeless_logs_dashboard,
        :historical_source,
        HistoricalSource.Local
      )

      {:ok, _} = Application.ensure_all_started(:timeless_logs)
      on_exit(fn -> TimelessLogs.unsubscribe() end)
      :ok
    end

    test "subscribe returns :ok, not Registry's {:ok, pid}" do
      assert :ok = HistoricalSource.subscribe()
    end

    test "subscribing twice is still :ok" do
      assert :ok = HistoricalSource.subscribe()
      assert :ok = HistoricalSource.subscribe()
    end

    test "unsubscribe returns :ok" do
      assert :ok = HistoricalSource.subscribe()
      assert :ok = HistoricalSource.unsubscribe()
    end
  end

  test "selected data-plane source fails closed when client is absent" do
    Application.put_env(
      :timeless_logs_dashboard,
      :historical_source,
      HistoricalSource.DataPlane
    )

    assert {:error, :missing_data_plane_client} = HistoricalSource.query([])
  end

  defmodule Client do
    def query(filters) do
      send(self(), {:logs_query, filters})
      {:ok, %{entries: [%{message: "kept"}], total: 1, has_more: false}}
    end

    def stats do
      {:ok,
       %{
         "total_entries" => 7,
         "compressed_blocks" => 2,
         "compressed_bytes" => 100,
         "raw_blocks" => 1,
         "raw_bytes" => 10
       }}
    end
  end
end
