defmodule TimelessLogsDashboard.ComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TimelessLogsDashboard.Components

  # The headline ratio is raw ingested bytes (the engine's persisted
  # logical-row counter) over stored data-block bytes — never file, WAL,
  # freelist, or index bytes. Older servers and pre-upgrade databases
  # report the counter as 0; the tile then falls back to the codec's
  # persisted input/output totals, exactly as before.
  describe "stats_tab compression ratio" do
    defp stats(overrides) do
      Map.merge(
        %{
          total_entries: 1_000,
          total_bytes: 100_000,
          storage_mode: :libsql,
          raw_blocks: 0,
          raw_bytes: 0,
          compressed_blocks: 4,
          compressed_bytes: 100_000,
          compression_raw_bytes_in: 0,
          compression_compressed_bytes_out: 0,
          raw_ingested_bytes_total: 0,
          oldest_timestamp: nil,
          newest_timestamp: nil
        },
        overrides
      )
    end

    test "uses raw ingested vs stored data-block bytes when the counter is present" do
      html =
        render_component(&Components.stats_tab/1,
          stats:
            stats(%{
              raw_ingested_bytes_total: 1_000_000,
              total_bytes: 100_000,
              # Codec totals disagree on purpose: the raw-based ratio must win.
              compression_raw_bytes_in: 500,
              compression_compressed_bytes_out: 100
            })
        )

      assert html =~ "10.0x (90.0% smaller)"
      refute html =~ "5.0x"
    end

    test "falls back to codec input/output totals when the raw counter is 0" do
      html =
        render_component(&Components.stats_tab/1,
          stats:
            stats(%{
              raw_ingested_bytes_total: 0,
              compression_raw_bytes_in: 500,
              compression_compressed_bytes_out: 100
            })
        )

      assert html =~ "5.0x (80.0% smaller)"
    end

    test "shows pending when only raw blocks exist and no ratio inputs" do
      html =
        render_component(&Components.stats_tab/1,
          stats: stats(%{raw_blocks: 3, raw_bytes: 300, compressed_blocks: 0})
        )

      assert html =~ "pending"
    end
  end

  describe "log entry rendering" do
    defp render_search(entry, overrides \\ %{}) do
      render_component(
        &Components.search_tab/1,
        Map.merge(
          %{
            entries: [entry],
            search: "",
            level: "",
            window: "24h",
            windows: TimelessLogsDashboard.Page.window_options(),
            current_page: 1,
            per_page: 25,
            has_more: false,
            page: nil,
            socket: nil
          },
          overrides
        )
      )
    end

    defp entry(metadata) do
      %{
        timestamp: 1_700_000_000_000_000,
        level: :info,
        message: "structured metadata",
        metadata: metadata
      }
    end

    test "non-String.Chars metadata values render safely" do
      html =
        render_search(
          entry(%{
            pid: self(),
            tuple: {:ok, 42},
            map: %{nested: true},
            list: [:not, :a, :charlist],
            trace_id: {:also, :structured}
          })
        )

      assert html =~ "#PID"
      assert html =~ "{:ok, 42}"
      assert html =~ "%{nested: true}"
      assert html =~ "[:not, :a, :charlist]"
      assert html =~ "{:also, :structured}"
    end

    test "large metadata is bounded by value length and key count" do
      metadata =
        1..11
        |> Map.new(fn key -> {"key-#{key}", String.duplicate(Integer.to_string(key), 500)} end)

      html = render_search(entry(metadata))

      assert html =~ "+1 more"
      refute html =~ String.duplicate("1", 500)
    end

    test "search summary does not claim the current page size is a total" do
      html = render_search(entry(%{}), %{has_more: false})

      assert html =~ "Showing 1 entry"
      assert html =~ "end of results"
      refute html =~ "of 1"
    end
  end
end
