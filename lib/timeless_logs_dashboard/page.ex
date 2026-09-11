defmodule TimelessLogsDashboard.Page do
  @moduledoc false
  use Phoenix.LiveDashboard.PageBuilder, refresher?: true

  import TimelessLogsDashboard.Components

  alias TimelessLogsDashboard.HistoricalSource

  @tail_cap 200

  # Ranges offered by the search form. "all" removes the bound entirely and is
  # the slow path, so it is opt-in rather than the default.
  @windows %{"1h" => 3_600, "24h" => 86_400, "7d" => 604_800, "30d" => 2_592_000}
  @default_window "24h"

  @impl true
  def menu_link(_, _) do
    {:ok, "TimelessLogs"}
  end

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(
        nav: resolve_nav(params),
        windows: window_options(),
        entries: [],
        has_more: false,
        stats: nil,
        subscribed: false,
        tail_error: nil,
        tail_count: 0,
        tail_sequence: 0,
        search: "",
        level: "",
        window: @default_window,
        since: "",
        until: "",
        trace_id: "",
        per_page: 25,
        current_page: 1
      )
      |> stream_configure(:tail_entries, dom_id: fn {id, _entry} -> "tail-entry-#{id}" end)
      |> stream(:tail_entries, [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_nav_bar
      id="log-tabs"
      page={@page}
      extra_params={[
        "search",
        "level",
        "window",
        "p",
        "per_page",
        "since",
        "until",
        "trace_id"
      ]}
    >
      <:item name="stats" label="Stats"><span></span></:item>
      <:item name="search" label="Search"><span></span></:item>
      <:item name="tail" label="Live Tail"><span></span></:item>
    </.live_nav_bar>
    <.search_tab
      :if={@nav == "search"}
      entries={@entries}
      search={@search}
      level={@level}
      window={@window}
      windows={@windows}
      current_page={@current_page}
      per_page={@per_page}
      has_more={@has_more}
      since={@since}
      until={@until}
      trace_id={@trace_id}
      page={@page}
      socket={@socket}
      traces_page={:traces}
    />
    <.stats_tab :if={@nav == "stats"} stats={@stats} />
    <.tail_tab
      :if={@nav == "tail"}
      stream={@streams.tail_entries}
      streaming
      entry_count={@tail_count}
      subscribed={@subscribed}
      error={@tail_error}
      page={@page}
      socket={@socket}
      traces_page={:traces}
    />
    """
  end

  @impl true
  def handle_params(params, _uri, socket) do
    nav = resolve_nav(params)

    if Map.get(params, "nav") == nav do
      socket =
        socket
        |> assign(:nav, nav)
        |> maybe_unsubscribe(nav)
        |> apply_nav(nav, params)

      {:noreply, socket}
    else
      to =
        live_dashboard_path(socket, socket.assigns.page, normalize_dashboard_params(params, nav))

      {:noreply, push_patch(socket, to: to)}
    end
  end

  defp apply_nav(socket, "search", params) do
    search = Map.get(params, "search", "")
    level = normalize_level(Map.get(params, "level", ""))
    window = params |> Map.get("window", @default_window) |> normalize_window()
    {since, since_filter} = timestamp_bound(Map.get(params, "since", ""), window)
    {until_param, until_filter} = optional_integer(Map.get(params, "until", ""))
    trace_id = Map.get(params, "trace_id", "")
    per_page = params |> Map.get("per_page", "25") |> integer_or(25) |> max(1) |> min(100)
    current_page = params |> Map.get("p", "1") |> integer_or(1) |> max(1)
    offset = (current_page - 1) * per_page

    filters = build_filters(search, level)
    filters = if since_filter, do: [{:since, since_filter} | filters], else: filters

    filters = if until_filter, do: [{:until, until_filter} | filters], else: filters

    filters =
      if trace_id != "", do: [{:metadata, %{"trace_id" => trace_id}} | filters], else: filters

    query_opts = filters ++ [limit: per_page, offset: offset, order: :desc, count_total: false]

    case HistoricalSource.query(query_opts) do
      {:ok, %{entries: entries} = result} ->
        has_more = Map.get(result, :has_more, false)

        assign(socket,
          entries: entries,
          has_more: has_more,
          search: search,
          level: level,
          window: window,
          since: since,
          until: until_param,
          trace_id: trace_id,
          per_page: per_page,
          current_page: current_page
        )

      {:error, _} ->
        assign(socket,
          entries: [],
          has_more: false,
          search: search,
          level: level,
          window: window,
          since: since,
          until: until_param,
          trace_id: trace_id,
          per_page: per_page,
          current_page: current_page
        )
    end
  end

  defp apply_nav(socket, "stats", _params) do
    case HistoricalSource.stats() do
      {:ok, stats} -> assign(socket, :stats, stats)
      _ -> socket
    end
  end

  defp apply_nav(socket, "tail", _params) do
    if connected?(socket) and not socket.assigns.subscribed do
      case HistoricalSource.subscribe() do
        :ok ->
          socket
          |> assign(subscribed: true, tail_count: 0, tail_error: nil)
          |> stream(:tail_entries, [], reset: true)

        {:error, reason} ->
          assign(socket, subscribed: false, tail_error: inspect(reason))
      end
    else
      socket
    end
  end

  defp apply_nav(socket, _, _params), do: socket

  defp maybe_unsubscribe(socket, "tail"), do: socket

  defp maybe_unsubscribe(socket, _nav) do
    if Map.get(socket.assigns, :subscribed, false) do
      case HistoricalSource.unsubscribe() do
        :ok -> assign(socket, subscribed: false, tail_error: nil)
        {:error, reason} -> assign(socket, subscribed: false, tail_error: inspect(reason))
      end
    else
      socket
    end
  end

  defp resolve_nav(params) do
    case Map.get(params, "nav") do
      nav when nav in ["search", "stats", "tail"] -> nav
      _ -> "stats"
    end
  end

  defp build_filters(search, level) do
    filters = []
    filters = if search != "", do: [{:message, search} | filters], else: filters

    case level_atom(level) do
      nil -> filters
      level_atom -> [{:level, level_atom} | filters]
    end
  end

  defp normalize_level(level) when level in ~w(debug info warning error), do: level
  defp normalize_level(_level), do: ""

  defp level_atom("debug"), do: :debug
  defp level_atom("info"), do: :info
  defp level_atom("warning"), do: :warning
  defp level_atom("error"), do: :error
  defp level_atom(_level), do: nil

  defp normalize_window("all"), do: "all"
  defp normalize_window(window) when is_map_key(@windows, window), do: window
  defp normalize_window(_window), do: @default_window

  defp integer_or(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> default
    end
  end

  defp integer_or(_value, default), do: default

  defp optional_integer(""), do: {"", nil}

  defp optional_integer(value) do
    case integer_or(value, nil) do
      nil -> {"", nil}
      integer -> {Integer.to_string(integer), integer}
    end
  end

  defp timestamp_bound(value, window) do
    case optional_integer(value) do
      {"", nil} ->
        case window_start(window) do
          "" -> {"", nil}
          default -> {"", String.to_integer(default)}
        end

      parsed ->
        parsed
    end
  end

  # A message search has no pushdown in the libSQL engine: the store returns
  # rows and the shared Filter applies the term, because :message also matches
  # metadata values and the engine can only match the message. Left unbounded
  # that decodes the whole store — measured at roughly 0.8s per 200k entries,
  # so several seconds against a real one, on every submit.
  #
  # A timestamp bound does push down, so the default range keeps the common
  # case cheap. It is a visible control rather than a hidden cap: "All time"
  # is still available, and a silent window would make older entries look
  # missing.
  @doc false
  def window_options,
    do: [
      {"1h", "Last hour"},
      {"24h", "Last 24 hours"},
      {"7d", "Last 7 days"},
      {"30d", "Last 30 days"},
      {"all", "All time"}
    ]

  defp window_start("all"), do: ""

  defp window_start(window) do
    case Map.fetch(@windows, window) do
      {:ok, seconds} ->
        DateTime.utc_now()
        |> DateTime.add(-seconds, :second)
        |> DateTime.to_unix(:microsecond)
        |> Integer.to_string()

      :error ->
        window_start(@default_window)
    end
  end

  defp normalize_dashboard_params(params, nav) do
    params
    |> Enum.map(fn
      {"search", value} -> {:search, value}
      {"level", value} -> {:level, value}
      {"p", value} -> {:p, value}
      {"per_page", value} -> {:per_page, value}
      {"window", value} -> {:window, value}
      {"since", value} -> {:since, value}
      {"until", value} -> {:until, value}
      {"trace_id", value} -> {:trace_id, value}
      {_key, _value} -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
    |> Map.put(:nav, nav)
  end

  @impl true
  def handle_event("search", %{"search" => search, "level" => level} = form, socket) do
    # Submitting the visible form starts a new search. Custom bounds and the
    # trace filter are intentionally reset because the form has no controls
    # for editing them; pagination, by contrast, preserves them verbatim.
    params = %{
      nav: "search",
      search: search,
      level: level,
      window: Map.get(form, "window", @default_window),
      since: "",
      until: "",
      trace_id: "",
      p: "1",
      per_page: to_string(socket.assigns.per_page)
    }

    to = live_dashboard_path(socket, socket.assigns.page, params)
    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("clear", _, socket) do
    params = %{nav: "search", search: "", level: "", window: @default_window, p: "1"}
    to = live_dashboard_path(socket, socket.assigns.page, params)
    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("toggle_tail", _, socket) do
    if socket.assigns.subscribed do
      case HistoricalSource.unsubscribe() do
        :ok -> {:noreply, assign(socket, subscribed: false, tail_error: nil)}
        {:error, reason} -> {:noreply, assign(socket, tail_error: inspect(reason))}
      end
    else
      case HistoricalSource.subscribe() do
        :ok ->
          socket =
            socket
            |> assign(subscribed: true, tail_count: 0, tail_error: nil)
            |> stream(:tail_entries, [], reset: true)

          {:noreply, socket}

        {:error, reason} ->
          {:noreply, assign(socket, tail_error: inspect(reason))}
      end
    end
  end

  @impl true
  def handle_refresh(socket) do
    socket =
      case socket.assigns.nav do
        "stats" -> apply_nav(socket, "stats", %{})
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:timeless_logs, :entry, entry}, socket) do
    if socket.assigns.nav == "tail" and socket.assigns.subscribed do
      sequence = socket.assigns.tail_sequence + 1

      socket =
        socket
        |> assign(
          tail_sequence: sequence,
          tail_count: min(socket.assigns.tail_count + 1, @tail_cap)
        )
        |> stream_insert(:tail_entries, {sequence, entry}, at: 0, limit: -@tail_cap)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}
end
