defmodule TimelessLogsDashboard.Page do
  @moduledoc false
  use Phoenix.LiveDashboard.PageBuilder, refresher?: false

  import TimelessLogsDashboard.Components

  @tail_cap 200

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
       stats: nil,
       tail_entries: [],
       subscribed: false,
       search: "",
       level: "",
       per_page: 25,
       current_page: 1
     )}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :nav, Map.get(assigns.page.params, "nav", "search"))

    ~H"""
    <.live_nav_bar
      id="log-tabs"
      page={@page}
      extra_params={["search", "level", "p", "per_page", "since", "until", "trace_id"]}
    >
      <:item name="search" label="Search"><span></span></:item>
      <:item name="stats" label="Stats"><span></span></:item>
      <:item name="tail" label="Live Tail"><span></span></:item>
    </.live_nav_bar>
    <.search_tab
      :if={@nav == "search"}
      entries={@entries}
      total={@total}
      search={@search}
      level={@level}
      current_page={@current_page}
      per_page={@per_page}
      page={@page}
      socket={@socket}
      traces_page={:traces}
    />
    <.stats_tab :if={@nav == "stats"} stats={@stats} />
    <.tail_tab :if={@nav == "tail"} entries={@tail_entries} subscribed={@subscribed} />
    """
  end

  @impl true
  def handle_params(params, _uri, socket) do
    nav = Map.get(params, "nav", "search")
    socket = apply_nav(nav, params, socket)
    {:noreply, socket}
  end

  defp apply_nav("search", params, socket) do
    search = Map.get(params, "search", "")
    level = Map.get(params, "level", "")
    since = Map.get(params, "since", "")
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

    query_opts = filters ++ [limit: per_page, offset: offset, order: :desc]

    case TimelessLogs.query(query_opts) do
      {:ok, %TimelessLogs.Result{entries: entries, total: total}} ->
        assign(socket,
          entries: entries,
          total: total,
          search: search,
          level: level,
          per_page: per_page,
          current_page: current_page
        )

      {:error, _} ->
        assign(socket,
          entries: [],
          total: 0,
          search: search,
          level: level,
          per_page: per_page,
          current_page: current_page
        )
    end
  end

  defp apply_nav("stats", _params, socket) do
    case TimelessLogs.stats() do
      {:ok, stats} -> assign(socket, :stats, stats)
      _ -> socket
    end
  end

  defp apply_nav("tail", _params, socket) do
    if connected?(socket) and not socket.assigns.subscribed do
      TimelessLogs.subscribe()
      assign(socket, subscribed: true, tail_entries: [])
    else
      socket
    end
  end

  defp apply_nav(_, _params, socket), do: socket

  defp build_filters(search, level) do
    filters = []
    filters = if search != "", do: [{:message, search} | filters], else: filters

    filters =
      if level != "", do: [{:level, String.to_existing_atom(level)} | filters], else: filters

    filters
  end

  @impl true
  def handle_event("search", %{"search" => search, "level" => level}, socket) do
    params = %{
      nav: "search",
      search: search,
      level: level,
      p: "1",
      per_page: to_string(socket.assigns.per_page)
    }

    to = live_dashboard_path(socket, socket.assigns.page, params)
    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("clear", _, socket) do
    params = %{nav: "search", search: "", level: "", p: "1"}
    to = live_dashboard_path(socket, socket.assigns.page, params)
    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("toggle_tail", _, socket) do
    if socket.assigns.subscribed do
      TimelessLogs.unsubscribe()
      {:noreply, assign(socket, subscribed: false)}
    else
      TimelessLogs.subscribe()
      {:noreply, assign(socket, subscribed: true, tail_entries: [])}
    end
  end

  @impl true
  def handle_info({:timeless_logs, :entry, entry}, socket) do
    tail = [entry | socket.assigns.tail_entries] |> Enum.take(@tail_cap)
    {:noreply, assign(socket, :tail_entries, tail)}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end
