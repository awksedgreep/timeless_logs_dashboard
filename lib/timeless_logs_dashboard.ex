defmodule TimelessLogsDashboard do
  @moduledoc """
  Phoenix LiveDashboard page for browsing TimelessLogs logs.

  ## Setup

  Add to your router:

      live_dashboard "/dashboard",
        additional_pages: [
          logs: TimelessLogsDashboard.Page
        ]

  Provides three tabs: **Search** (query with filters + pagination),
  **Stats** (aggregate metrics), and **Live Tail** (real-time streaming).
  """
end
