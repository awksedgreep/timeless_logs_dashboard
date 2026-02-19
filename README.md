# TimelessLogsDashboard

Phoenix [LiveDashboard](https://github.com/phoenixframework/phoenix_live_dashboard) page for browsing [TimelessLogs](https://github.com/awksedgreep/timeless_logs) logs.

Provides three tabs:

- **Search** -- query logs with level, message, and metadata filters + pagination
- **Stats** -- aggregate metrics (blocks, entries, compressed size, index size, timestamps)
- **Live Tail** -- real-time streaming of new log entries

## Installation

### Quick Start (Igniter)

```bash
mix igniter.install timeless_logs_dashboard
```

This automatically:
1. Adds `config :timeless_logs, data_dir: "priv/timeless_logs"` to your config
2. Adds `import TimelessLogsDashboard.Router` to your router
3. Adds `timeless_logs_dashboard "/dashboard"` to your browser scope
4. Updates your `.formatter.exs`

For in-memory storage (logs lost on restart):

```bash
mix igniter.install timeless_logs_dashboard --storage memory
```

### Manual Setup

Add `timeless_logs_dashboard` to your dependencies:

```elixir
def deps do
  [
    {:timeless_logs_dashboard, "~> 0.6.0"}
  ]
end
```

Configure TimelessLogs in `config/config.exs`:

```elixir
config :timeless_logs, data_dir: "priv/timeless_logs"
```

Add the router macro:

```elixir
# lib/my_app_web/router.ex
import TimelessLogsDashboard.Router

scope "/" do
  pipe_through :browser
  timeless_logs_dashboard "/dashboard"
end
```

Or add the page directly to an existing LiveDashboard:

```elixir
live_dashboard "/dashboard",
  additional_pages: [
    logs: TimelessLogsDashboard.Page
  ]
```

Navigate to `/dashboard/logs` in your browser.

## Requirements

- [TimelessLogs](https://github.com/awksedgreep/timeless_logs) must be running in your application
- Phoenix LiveDashboard ~> 0.8
- Phoenix LiveView ~> 1.0

## License

MIT
