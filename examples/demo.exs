# Minimal Phoenix app to demo TimelessLogsDashboard.
#
# Run:  mix run examples/demo.exs
# Open: http://localhost:4040/dashboard/logs
# Stop: Ctrl+C twice

Logger.configure(level: :info)

# --- Phoenix Endpoint + Router ---

defmodule Demo.ErrorHTML do
  def render(template, _assigns), do: "Error: #{template}"
end

defmodule Demo.Router do
  use Phoenix.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser

    live_dashboard "/dashboard",
      additional_pages: [
        logs: TimelessLogsDashboard.Page
      ]
  end
end

defmodule Demo.Endpoint do
  use Phoenix.Endpoint, otp_app: :timeless_logs_dashboard

  @session_options [
    store: :cookie,
    key: "_demo_key",
    signing_salt: "demo_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.Session, @session_options
  plug Demo.Router
end

# --- Boot everything ---

# Phoenix needs a JSON library
Application.put_env(:phoenix, :json_library, Jason)

# Configure endpoint
Application.put_env(:timeless_logs_dashboard, Demo.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [port: 4040],
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "demo_lv_salt"],
  pubsub_server: Demo.PubSub,
  render_errors: [formats: [html: Demo.ErrorHTML], layout: false],
  debug_errors: true,
  server: true
)

# Stop log_stream (auto-started by mix run with disk defaults),
# reconfigure for in-memory mode, then restart
Application.stop(:timeless_logs)
Application.put_env(:timeless_logs, :storage, :memory)
Application.put_env(:timeless_logs, :flush_interval, 5_000)
Application.put_env(:timeless_logs, :max_buffer_size, 500)
Application.put_env(:timeless_logs, :compaction_interval, 10_000)
Application.put_env(:timeless_logs, :compaction_threshold, 500)
Application.put_env(:timeless_logs, :compaction_max_raw_age, 30)

# Start deps
{:ok, _} = Application.ensure_all_started(:phoenix_live_dashboard)

# Start PubSub (required by LiveView)
{:ok, _} =
  Supervisor.start_link(
    [{Phoenix.PubSub, name: Demo.PubSub}],
    strategy: :one_for_one
  )

# Restart TimelessLogs with memory config
{:ok, _} = Application.ensure_all_started(:timeless_logs)

# Start endpoint
{:ok, _} = Demo.Endpoint.start_link()

IO.puts("""

========================================
  TimelessLogsDashboard Demo
  http://localhost:4040/dashboard/logs
========================================

Generating sample log entries every second...
Press Ctrl+C twice to stop.
""")

# Generate sample log data in a loop
require Logger

sample_messages = [
  {"User logged in", :info, %{user_id: "123", service: "auth"}},
  {"Database query completed", :debug, %{duration_ms: "42", table: "users"}},
  {"Request timeout", :warning, %{endpoint: "/api/search", timeout_ms: "5000"}},
  {"Connection refused", :error, %{host: "db-replica-2", port: "5432"}},
  {"Cache hit", :info, %{cache: "redis", key: "session:abc"}},
  {"Payment processed", :info, %{amount: "$29.99", provider: "stripe"}},
  {"Rate limit exceeded", :warning, %{ip: "192.168.1.100", limit: "100/min"}},
  {"SSL certificate expiring soon", :warning, %{domain: "api.example.com", days: "7"}},
  {"Worker completed job", :info, %{job_id: "j-9001", queue: "default"}},
  {"Unhandled exception in controller", :error, %{module: "UserController", action: "show"}}
]

Stream.interval(500)
|> Stream.each(fn _ ->
  # Pick 5-10 random messages per tick (~15-20/sec → ~500 in 30s)
  count = Enum.random(5..10)

  for _ <- 1..count do
    {msg, level, meta} = Enum.random(sample_messages)
    Logger.log(level, msg, Map.to_list(meta))
  end
end)
|> Stream.run()
