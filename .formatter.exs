# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  import_deps: [:phoenix_live_view],
  export: [
    locals_without_parens: [timeless_logs_dashboard: 1, timeless_logs_dashboard: 2]
  ]
]
