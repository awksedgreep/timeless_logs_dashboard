<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="docs/logo-light.svg">
    <img src="docs/logo-light.svg" width="300" alt="Timeless">
  </picture>
</p>

<h3 align="center">LiveDashboard Plugin for Timeless Logs</h3>

<p align="center">
  <a href="https://hex.pm/packages/timeless_logs_dashboard"><img src="https://img.shields.io/hexpm/v/timeless_logs_dashboard.svg" alt="Hex.pm"></a>
  <a href="https://hexdocs.pm/timeless_logs_dashboard"><img src="https://img.shields.io/badge/docs-hexdocs-blue.svg" alt="Docs"></a>
  <a href="LICENSE"><img src="https://img.shields.io/hexpm/l/timeless_logs_dashboard.svg" alt="License"></a>
</p>

---

> "I found it ironic that the first thing you do to time series data is squash the timestamp. That's how the name Timeless was born." --Mark Cotner

Phoenix [LiveDashboard](https://github.com/phoenixframework/phoenix_live_dashboard) page for browsing [TimelessLogs](https://github.com/awksedgreep/timeless_logs) logs.

Provides three tabs:

- **Search** -- query logs with level, message, and metadata filters, a
  visible time-range control, and pagination
- **Stats** -- entries, total size, storage mode and engine, raw and
  compressed blocks, durable compression ratio with storage efficiency, and
  oldest/newest timestamps
- **Live Tail** -- real-time streaming of new log entries; trace ids in
  entries link through to the traces dashboard

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
    {:timeless_logs_dashboard, "~> 0.7"}
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

## Reading from the Rust data plane

By default the dashboard reads the embedded TimelessLogs store. It can
instead delegate reads to a Rust logs data plane through a configured HTTP
client (such as the release Stack adapter):

```elixir
config :timeless_logs_dashboard,
  historical_source:
    {TimelessLogsDashboard.HistoricalSource.DataPlane, client: MyStack.LogsClient}
```

The client must implement `query/1` and `stats/0`. Live tail also works over
the data plane when the client additionally exports `tail/3` (streaming
`/select/logsql/tail`); with a tail-less client, the Live Tail tab fails
explicitly instead of silently consulting the embedded store.

## Requirements

- [TimelessLogs](https://github.com/awksedgreep/timeless_logs) must be running in your application
- Phoenix LiveDashboard ~> 0.8
- Phoenix LiveView ~> 1.0

## License

MIT
