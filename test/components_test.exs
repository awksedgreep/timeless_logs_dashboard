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
end
