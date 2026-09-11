defmodule TimelessLogsDashboard.PageLifecycleTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Phoenix.LiveDashboard.PageBuilder
  alias TimelessLogsDashboard.Components
  alias TimelessLogsDashboard.Page

  defmodule Router do
    use Phoenix.Router
    import Phoenix.LiveDashboard.Router

    scope "/" do
      live_dashboard("/dashboard", additional_pages: [logs: TimelessLogsDashboard.Page])
    end
  end

  defmodule Endpoint do
    def path(path), do: path
    def script_name, do: []
    def config(:render_errors), do: []
    def config(_key), do: nil
  end

  defmodule Recorder do
    @behaviour TimelessLogsDashboard.HistoricalSource

    @impl true
    def query(_filters, _opts), do: {:ok, %{entries: [], has_more: false}}

    @impl true
    def stats(_opts), do: {:ok, %{}}

    @impl true
    def subscribe(_opts) do
      send(self(), :subscribed)
      :ok
    end

    @impl true
    def unsubscribe(_opts) do
      send(self(), :unsubscribed)
      :ok
    end
  end

  setup do
    previous = Application.get_env(:timeless_logs_dashboard, :historical_source)
    Application.put_env(:timeless_logs_dashboard, :historical_source, Recorder)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:timeless_logs_dashboard, :historical_source, previous),
        else: Application.delete_env(:timeless_logs_dashboard, :historical_source)
    end)
  end

  test "leaving live tail unsubscribes and ignores later entries" do
    socket = mounted_socket(%{"nav" => "tail"})
    {:noreply, socket} = Page.handle_params(%{"nav" => "tail"}, "/", socket)

    assert_receive :subscribed
    assert socket.assigns.subscribed

    entry = %{timestamp: 1, level: :info, message: "first", metadata: %{}}
    {:noreply, socket} = Page.handle_info({:timeless_logs, :entry, entry}, socket)

    assert socket.assigns.tail_count == 1

    assert [{_dom_id, 0, {_sequence, ^entry}, -200, false}] =
             socket.assigns.streams.tail_entries.inserts

    {:noreply, socket} = Page.handle_params(%{"nav" => "stats"}, "/", socket)

    assert_receive :unsubscribed
    refute socket.assigns.subscribed
    assert socket.assigns.nav == "stats"

    later = %{entry | message: "should be ignored"}
    {:noreply, socket} = Page.handle_info({:timeless_logs, :entry, later}, socket)

    assert socket.assigns.tail_count == 1
  end

  test "mount computes stable navigation and range assigns" do
    socket = mounted_socket(%{"nav" => "search"})

    assert socket.assigns.nav == "search"
    assert socket.assigns.windows == Page.window_options()
  end

  test "tail rows render through a LiveView stream container" do
    socket = mounted_socket(%{"nav" => "tail"})
    {:noreply, socket} = Page.handle_params(%{"nav" => "tail"}, "/", socket)

    assert_receive :subscribed

    entry = %{timestamp: 1, level: :info, message: "stream row", metadata: %{}}
    {:noreply, socket} = Page.handle_info({:timeless_logs, :entry, entry}, socket)

    html =
      render_component(&Components.tail_tab/1,
        stream: socket.assigns.streams.tail_entries,
        streaming: true,
        entry_count: socket.assigns.tail_count,
        subscribed: socket.assigns.subscribed,
        page: socket.assigns.page,
        socket: socket,
        traces_page: :traces
      )

    assert html =~ ~s(id="tail-entries")
    assert html =~ ~s(phx-update="stream")
    assert html =~ ~s(id="tail-entry-1")
    assert html =~ "stream row"
  end

  defp mounted_socket(params) do
    socket = %Phoenix.LiveView.Socket{
      transport_pid: self(),
      router: Router,
      endpoint: Endpoint,
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}},
      assigns: %{
        __changed__: %{},
        page: %PageBuilder{params: params, route: :logs, node: nil}
      }
    }

    assert {:ok, socket} = Page.mount(params, %{}, socket)
    socket
  end
end
