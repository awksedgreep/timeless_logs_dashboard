defmodule TimelessLogsDashboard.Components do
  @moduledoc false
  use Phoenix.Component

  # --- Search tab ---

  attr(:entries, :list, required: true)
  attr(:total, :integer, required: true)
  attr(:search, :string, required: true)
  attr(:level, :string, required: true)
  attr(:window, :string, required: true)
  attr(:windows, :list, required: true)
  attr(:current_page, :integer, required: true)
  attr(:per_page, :integer, required: true)
  attr(:has_more, :boolean, required: true)
  attr(:page, :any, required: true)
  attr(:socket, :any, required: true)
  attr(:traces_page, :atom, default: nil)

  def search_tab(assigns) do
    levels = ~w(debug info warning error)
    assigns = assigns |> assign(:levels, levels)

    ~H"""
    <div class="mb-4">
      <div class="d-flex align-items-end mb-3" style="gap: 0.75rem;">
        <form phx-submit="search" class="d-flex align-items-end" style="gap: 0.75rem;">
          <div>
            <label class="form-label mb-1"><small>Message</small></label>
            <input
              type="text"
              name="search"
              value={@search}
              placeholder="Search messages..."
              class="form-control form-control-sm"
              style="min-width: 240px;"
            />
          </div>
          <div>
            <label class="form-label mb-1"><small>Level</small></label>
            <select name="level" class="form-select form-select-sm" style="min-width: 120px;">
              <option value="" selected={@level == ""}>All</option>
              <option :for={l <- @levels} value={l} selected={@level == l}>
                {String.capitalize(l)}
              </option>
            </select>
          </div>
          <div>
            <label class="form-label mb-1"><small>Range</small></label>
            <select name="window" class="form-select form-select-sm" style="min-width: 140px;">
              <option :for={{value, label} <- @windows} value={value} selected={@window == value}>
                {label}
              </option>
            </select>
          </div>
          <button type="submit" class="btn btn-primary btn-sm">Search</button>
        </form>
        <button phx-click="clear" class="btn btn-outline-secondary btn-sm">
          Clear
        </button>
      </div>

      <div class="card">
        <div class="card-body p-0">
          <div class="d-flex justify-content-between align-items-center px-3 py-2">
            <small class="text-muted">
              Showing {length(@entries)} {if length(@entries) == 1, do: "entry", else: "entries"} of {@total} in {window_label(
                @windows,
                @window
              )}
            </small>
            <small class="text-muted">
              Page {@current_page}
            </small>
          </div>
          <table class="table table-sm table-hover mb-0">
            <thead>
              <tr>
                <th style="width: 180px;">Timestamp</th>
                <th style="width: 80px;">Level</th>
                <th>Message</th>
                <th style="width: 200px;">Metadata</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@entries == []}>
                <td colspan="4" class="text-center text-muted py-4">No log entries found.</td>
              </tr>
              <.entry_row
                :for={entry <- @entries}
                entry={entry}
                page={@page}
                socket={@socket}
                traces_page={@traces_page}
              />
            </tbody>
          </table>
          <.pagination
            :if={@current_page > 1 or @has_more}
            current_page={@current_page}
            has_more={@has_more}
            window={@window}
            page={@page}
            socket={@socket}
            search={@search}
            level={@level}
            per_page={@per_page}
          />
        </div>
      </div>
    </div>
    """
  end

  attr(:entry, :any, required: true)
  attr(:page, :any, default: nil)
  attr(:socket, :any, default: nil)
  attr(:traces_page, :atom, default: nil)

  defp entry_row(assigns) do
    meta = assigns.entry.metadata || %{}

    trace_id =
      Map.get(meta, "trace_id") || Map.get(meta, :trace_id) ||
        Map.get(meta, "otel_trace_id") || Map.get(meta, :otel_trace_id)

    other_meta =
      meta
      |> Map.drop([
        "trace_id",
        :trace_id,
        "otel_trace_id",
        :otel_trace_id,
        "span_id",
        :span_id,
        "otel_span_id",
        :otel_span_id
      ])

    trace_link =
      if trace_id && assigns.traces_page && assigns.socket && assigns.page do
        Phoenix.LiveDashboard.PageBuilder.live_dashboard_path(
          assigns.socket,
          assigns.traces_page,
          assigns.page.node,
          %{},
          %{"nav" => "traces", "trace_id" => to_string(trace_id)}
        )
      end

    assigns =
      assigns
      |> assign(:trace_id, trace_id)
      |> assign(:trace_link, trace_link)
      |> assign(:other_meta, other_meta)

    ~H"""
    <tr>
      <td class="text-monospace" style="font-size: 0.8rem;">
        {format_timestamp(@entry.timestamp)}
      </td>
      <td><.level_badge level={@entry.level} /></td>
      <td style="max-width: 500px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
        {@entry.message}
      </td>
      <td style="font-size: 0.8rem;">
        <span :if={@trace_id}>
          <a
            :if={@trace_link}
            href={@trace_link}
            style="color: #2563eb; text-decoration: none; font-family: monospace;"
            title={"View trace #{@trace_id}"}
          >
            trace_id={String.slice(to_string(@trace_id), 0..11)}...
          </a>
          <span :if={!@trace_link} style="font-family: monospace;">trace_id={@trace_id}</span>
          <span :if={@other_meta != %{}}>, </span>
        </span>
        {format_metadata(@other_meta)}
      </td>
    </tr>
    """
  end

  attr(:level, :any, required: true)

  defp level_badge(assigns) do
    color =
      case to_string(assigns.level) do
        "error" -> "danger"
        "warning" -> "warning"
        "info" -> "info"
        "debug" -> "secondary"
        _ -> "light"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={"badge bg-#{@color}"} style="font-size: 0.7rem;">
      {@level}
    </span>
    """
  end

  attr(:current_page, :integer, required: true)
  attr(:has_more, :boolean, required: true)
  attr(:page, :any, required: true)
  attr(:socket, :any, required: true)
  attr(:search, :string, required: true)
  attr(:level, :string, required: true)
  attr(:window, :string, required: true)
  attr(:per_page, :integer, required: true)

  defp pagination(assigns) do
    assigns =
      assigns
      |> assign(:prev_page, max(assigns.current_page - 1, 1))
      |> assign(:next_page, assigns.current_page + 1)

    ~H"""
    <nav class="d-flex justify-content-center py-2">
      <ul class="pagination pagination-sm mb-0">
        <li class={"page-item #{if @current_page <= 1, do: "disabled"}"}>
          <span :if={@current_page <= 1} class="page-link">Prev</span>
          <.link
            :if={@current_page > 1}
            patch={page_path(@socket, @page, @prev_page, @search, @level, @window, @per_page)}
            class="page-link"
          >
            Prev
          </.link>
        </li>
        <li class="page-item disabled">
          <span class="page-link">Page {@current_page}</span>
        </li>
        <li class={"page-item #{if not @has_more, do: "disabled"}"}>
          <span :if={not @has_more} class="page-link">Next</span>
          <.link
            :if={@has_more}
            patch={page_path(@socket, @page, @next_page, @search, @level, @window, @per_page)}
            class="page-link"
          >
            Next
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  # The range has to travel with the page number. Without it, paging falls back
  # to the default window, so a search over "All time" or "Last 7 days" would
  # silently return 24-hour results from page two onward — with a different
  # total than the one that produced the pager.
  defp page_path(socket, page, page_num, search, level, window, per_page) do
    Phoenix.LiveDashboard.PageBuilder.live_dashboard_path(
      socket,
      page,
      page_params(page_num, search, level, window, per_page)
    )
  end

  @doc false
  # Split out from page_path/7 so it can be asserted without a router. The
  # range has to travel with the page number: without it, paging falls back to
  # the default window, so a search over "All time" or "Last 7 days" would
  # silently return 24-hour results from page two onward — with a total that no
  # longer matches the pager that produced it.
  def page_params(page_num, search, level, window, per_page) do
    %{
      nav: "search",
      search: search,
      level: level,
      window: window,
      p: to_string(page_num),
      per_page: to_string(per_page)
    }
  end

  # --- Stats tab ---

  attr(:stats, :any, required: true)

  def stats_tab(assigns) do
    ~H"""
    <div :if={@stats == nil} class="text-center text-muted py-4">
      Loading stats...
    </div>
    <div :if={@stats} class="row">
      <div class="col-sm-4 mb-3">
        <div class="card">
          <div class="card-body text-center">
            <h6 class="card-subtitle text-muted mb-1">Total Entries</h6>
            <h4 class="mb-0">{@stats.total_entries}</h4>
          </div>
        </div>
      </div>
      <div class="col-sm-4 mb-3">
        <div class="card">
          <div class="card-body text-center">
            <h6 class="card-subtitle text-muted mb-1">Total Size</h6>
            <h4 class="mb-0">{format_bytes(@stats.total_bytes)}</h4>
          </div>
        </div>
      </div>
      <div class="col-sm-4 mb-3">
        <div class="card">
          <div class="card-body text-center">
            <h6 class="card-subtitle text-muted mb-1">Storage Mode</h6>
            <h4 class="mb-0">
              <span class="badge bg-info">{Map.get(
                @stats,
                :storage_mode,
                TimelessLogs.Config.storage()
              )}</span>
            </h4>
          </div>
        </div>
      </div>
      <div class="col-sm-4 mb-3">
        <div class="card">
          <div class="card-body text-center">
            <h6 class="card-subtitle text-muted mb-1">Raw Blocks</h6>
            <h4 class="mb-0">
              {@stats.raw_blocks}
              <small class="text-muted" style="font-size: 0.6em;">
                ({format_bytes(@stats.raw_bytes)})
              </small>
            </h4>
          </div>
        </div>
      </div>
      <div class="col-sm-4 mb-3">
        <div class="card">
          <div class="card-body text-center">
            <h6 class="card-subtitle text-muted mb-1">Compressed Blocks</h6>
            <% compressed_blocks = @stats.zstd_blocks + Map.get(@stats, :openzl_blocks, 0) %>
            <% compressed_bytes = @stats.zstd_bytes + Map.get(@stats, :openzl_bytes, 0) %>
            <h4 class="mb-0">
              {compressed_blocks}
              <small class="text-muted" style="font-size: 0.6em;">
                ({format_bytes(compressed_bytes)})
              </small>
            </h4>
          </div>
        </div>
      </div>
      <div class="col-sm-4 mb-3">
        <div class="card">
          <div class="card-body text-center">
            <h6 class="card-subtitle text-muted mb-1">Data Compression</h6>
            <h4 class="mb-0">
              {if Map.get(@stats, :compression_raw_bytes_in, 0) > 0 and
                    Map.get(@stats, :compression_compressed_bytes_out, 0) > 0 do
                ratio = @stats.compression_raw_bytes_in / @stats.compression_compressed_bytes_out
                pct = Float.round((1 - 1 / ratio) * 100, 1)
                "#{Float.round(ratio, 1)}x (#{pct}%)"
              else
                if Map.get(@stats, :compaction_count, 0) > 0, do: "1.0x (0%)", else: "pending"
              end}
            </h4>
          </div>
        </div>
      </div>
      <div class="col-sm-4 mb-3">
        <div class="card">
          <div class="card-body text-center">
            <h6 class="card-subtitle text-muted mb-1">Oldest Entry</h6>
            <h4 class="mb-0" style="font-size: 1rem;">
              {format_timestamp(@stats.oldest_timestamp)}
            </h4>
          </div>
        </div>
      </div>
      <div class="col-sm-4 mb-3">
        <div class="card">
          <div class="card-body text-center">
            <h6 class="card-subtitle text-muted mb-1">Newest Entry</h6>
            <h4 class="mb-0" style="font-size: 1rem;">
              {format_timestamp(@stats.newest_timestamp)}
            </h4>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Live Tail tab ---

  attr(:entries, :list, required: true)
  attr(:subscribed, :boolean, required: true)
  attr(:error, :string, default: nil)
  attr(:page, :any, default: nil)
  attr(:socket, :any, default: nil)
  attr(:traces_page, :atom, default: nil)

  def tail_tab(assigns) do
    ~H"""
    <div class="mb-4">
      <div :if={@error} class="alert alert-warning" role="alert">{@error}</div>
      <div class="d-flex align-items-center mb-3" style="gap: 0.75rem;">
        <button
          phx-click="toggle_tail"
          class={"btn btn-sm #{if @subscribed, do: "btn-danger", else: "btn-success"}"}
        >
          {if @subscribed, do: "Stop", else: "Start"}
        </button>
        <small class="text-muted">
          <%= if @subscribed do %>
            Streaming... ({length(@entries)} entries)
          <% else %>
            Paused
          <% end %>
        </small>
      </div>

      <div class="card">
        <div class="card-body p-0">
          <table class="table table-sm table-hover mb-0">
            <thead>
              <tr>
                <th style="width: 180px;">Timestamp</th>
                <th style="width: 80px;">Level</th>
                <th>Message</th>
                <th style="width: 200px;">Metadata</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@entries == []}>
                <td colspan="4" class="text-center text-muted py-4">
                  {if @subscribed,
                    do: "Waiting for log entries...",
                    else: "Click Start to begin streaming."}
                </td>
              </tr>
              <.entry_row
                :for={entry <- @entries}
                entry={entry}
                page={@page}
                socket={@socket}
                traces_page={@traces_page}
              />
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(ts) when is_integer(ts) do
    # timeless_logs >= 1.5 uses canonical microseconds; older versions
    # mixed seconds (logger handler) and microseconds (jsonline). Detect
    # the unit by magnitude so both display correctly.
    case DateTime.from_unix(ts, timestamp_unit(ts)) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      _ -> to_string(ts)
    end
  end

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_timestamp(other), do: to_string(other)

  defp timestamp_unit(ts) when ts >= 100_000_000_000_000_000, do: :nanosecond
  defp timestamp_unit(ts) when ts >= 100_000_000_000_000, do: :microsecond
  defp timestamp_unit(ts) when ts >= 100_000_000_000, do: :millisecond
  defp timestamp_unit(_ts), do: :second

  defp format_metadata(nil), do: ""
  defp format_metadata(meta) when meta == %{}, do: ""

  defp format_metadata(meta) when is_map(meta) do
    meta
    |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp format_bytes(nil), do: "-"
  defp format_bytes(0), do: "0 B"

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp window_label(windows, window) do
    Enum.find_value(windows, window, fn {value, label} ->
      if value == window, do: String.downcase(label)
    end)
  end
end
