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
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       entries: [],
       total: 0,
       has_more: false,
       stats: nil,
       tail_entries: [],
       subscribed: false,
       tail_error: nil,
       search: "",
       level: "",
       window: @default_window,
       per_page: 25,
       current_page: 1
     )}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:nav, resolve_nav(assigns.page.params))
      |> assign(:windows, window_options())

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
      total={@total}
      search={@search}
      level={@level}
      window={@window}
      windows={@windows}
      current_page={@current_page}
      per_page={@per_page}
      has_more={@has_more}
      page={@page}
      socket={@socket}
      traces_page={:traces}
    />
    <.stats_tab :if={@nav == "stats"} stats={@stats} />
    <.tail_tab
      :if={@nav == "tail"}
      entries={@tail_entries}
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
      socket = apply_nav(nav, params, socket)
      {:noreply, socket}
    else
      to =
        live_dashboard_path(socket, socket.assigns.page, normalize_dashboard_params(params, nav))

      {:noreply, push_patch(socket, to: to)}
    end
  end

  defp apply_nav("search", params, socket) do
    search = Map.get(params, "search", "")
    level = Map.get(params, "level", "")
    window = Map.get(params, "window", @default_window)
    since = params |> Map.get("since", "") |> default_since(window)
    until_param = Map.get(params, "until", "")
    trace_id = Map.get(params, "trace_id", "")
    per_page = params |> Map.get("per_page", "25") |> String.to_integer() |> max(1) |> min(100)
    current_page = params |> Map.get("p", "1") |> String.to_integer() |> max(1)
    offset = (current_page - 1) * per_page

    filters = build_filters(search, level)
    filters = if since != "", do: [{:since, String.to_integer(since)} | filters], else: filters

    filters =
      if until_param != "",
        do: [{:until, String.to_integer(until_param)} | filters],
        else: filters

    filters =
      if trace_id != "", do: [{:metadata, %{"trace_id" => trace_id}} | filters], else: filters

    query_opts = filters ++ [limit: per_page, offset: offset, order: :desc, count_total: false]

    case HistoricalSource.query(query_opts) do
      {:ok, %{entries: entries} = result} ->
        total = Map.get(result, :total, length(entries))
        has_more = Map.get(result, :has_more, false)

        assign(socket,
          entries: entries,
          total: total,
          has_more: has_more,
          search: search,
          level: level,
          window: window,
          per_page: per_page,
          current_page: current_page
        )

      {:error, _} ->
        assign(socket,
          entries: [],
          total: 0,
          has_more: false,
          search: search,
          level: level,
          window: window,
          per_page: per_page,
          current_page: current_page
        )
    end
  end

  defp apply_nav("stats", _params, socket) do
    case HistoricalSource.stats() do
      {:ok, stats} -> assign(socket, :stats, stats)
      _ -> socket
    end
  end

  defp apply_nav("tail", _params, socket) do
    if connected?(socket) and not socket.assigns.subscribed do
      case HistoricalSource.subscribe() do
        :ok -> assign(socket, subscribed: true, tail_entries: [], tail_error: nil)
        {:error, reason} -> assign(socket, subscribed: false, tail_error: inspect(reason))
      end
    else
      socket
    end
  end

  defp apply_nav(_, _params, socket), do: socket

  defp resolve_nav(params) do
    case Map.get(params, "nav") do
      nav when nav in ["search", "stats", "tail"] -> nav
      _ -> "stats"
    end
  end

  defp build_filters(search, level) do
    filters = []
    filters = if search != "", do: [{:message, search} | filters], else: filters

    filters =
      if level != "", do: [{:level, String.to_existing_atom(level)} | filters], else: filters

    filters
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

  defp default_since("", window), do: window_start(window)
  defp default_since(since, _window), do: since

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
    params = %{
      nav: "search",
      search: search,
      level: level,
      window: Map.get(form, "window", @default_window),
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
        :ok -> {:noreply, assign(socket, subscribed: true, tail_entries: [], tail_error: nil)}
        {:error, reason} -> {:noreply, assign(socket, tail_error: inspect(reason))}
      end
    end
  end

  @impl true
  def handle_refresh(socket) do
    nav = resolve_nav(socket.assigns.page.params)

    socket =
      case nav do
        "stats" -> apply_nav("stats", %{}, socket)
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:timeless_logs, :entry, entry}, socket) do
    tail = [entry | socket.assigns.tail_entries] |> Enum.take(@tail_cap)
    {:noreply, assign(socket, :tail_entries, tail)}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end
