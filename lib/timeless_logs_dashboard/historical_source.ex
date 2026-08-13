defmodule TimelessLogsDashboard.HistoricalSource do
  @moduledoc """
  Configurable owner boundary for dashboard reads and live-tail subscription.

  The local source preserves the embedded-library behavior. The data-plane
  source delegates historical reads to one configured Rust HTTP client and
  rejects live tail explicitly; it never falls back to `TimelessLogs`.
  """

  @callback query(keyword(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback stats(keyword()) :: {:ok, map()} | {:error, term()}
  @callback subscribe(keyword()) :: :ok | {:error, term()}
  @callback unsubscribe(keyword()) :: :ok | {:error, term()}

  @default TimelessLogsDashboard.HistoricalSource.Local

  def query(filters), do: call(:query, [filters])
  def stats, do: call(:stats, [])
  def subscribe, do: call(:subscribe, [])
  def unsubscribe, do: call(:unsubscribe, [])

  defp call(function, args) do
    case Application.get_env(:timeless_logs_dashboard, :historical_source, @default) do
      {module, opts} when is_atom(module) and is_list(opts) ->
        apply(module, function, args ++ [opts])

      module when is_atom(module) ->
        apply(module, function, args ++ [[]])
    end
  end
end

defmodule TimelessLogsDashboard.HistoricalSource.Local do
  @moduledoc false
  @behaviour TimelessLogsDashboard.HistoricalSource

  @impl true
  def query(filters, _opts), do: TimelessLogs.query(filters)

  @impl true
  def stats(_opts), do: TimelessLogs.stats()

  # TimelessLogs.subscribe/0 delegates straight to Registry.register/3, which
  # answers {:ok, pid} — never a bare :ok. Returning that unchanged breaks the
  # `:ok | {:error, term()}` contract this module declares, and callers that
  # match the contract crash with a CaseClauseError on the success path.
  #
  # Already being registered also means the caller will receive entries, so it
  # is success rather than an error.
  @impl true
  def subscribe(_opts) do
    case TimelessLogs.subscribe() do
      {:ok, _pid} -> :ok
      {:error, {:already_registered, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Registry.unregister/2 always answers :ok, so there is no failure to map.
  @impl true
  def unsubscribe(_opts) do
    TimelessLogs.unsubscribe()
  end
end

defmodule TimelessLogsDashboard.HistoricalSource.DataPlane do
  @moduledoc """
  Historical source for a configured Rust logs HTTP client.

  Set `:client` to a module implementing `query/1` and `stats/0`, such as the
  release Stack adapter. A two-argument client can instead be supplied with
  `:client_opts`. Live tail is not part of the first release API and fails
  explicitly rather than starting or consulting the embedded owner.
  """

  @behaviour TimelessLogsDashboard.HistoricalSource

  @impl true
  def query(filters, opts), do: invoke(opts, :query, [filters])

  @impl true
  def stats(opts) do
    with {:ok, stats} <- invoke(opts, :stats, []) do
      {:ok, normalize_stats(stats)}
    end
  end

  # Live tail over the data plane: the client streams
  # /select/logsql/tail and delivers {:timeless_logs, :entry, entry} to the
  # calling process — the same messages the embedded Registry tail sends, so
  # the page cannot tell the sources apart. subscribe/unsubscribe both run
  # in the page's own process (the page calls them directly), so the
  # streaming task's pid lives in that process's dictionary; killing it
  # closes the connection, which unsubscribes server-side.
  @impl true
  def subscribe(opts) do
    with {:ok, client} <- Keyword.fetch(opts, :client) do
      cond do
        not function_exported?(client, :tail, 3) ->
          {:error, {:unsupported_capability, :logs_live_tail}}

        Process.get({__MODULE__, :tail_task}) != nil ->
          :ok

        true ->
          case client.tail("*", self(), Keyword.get(opts, :client_opts, [])) do
            {:ok, task} ->
              Process.put({__MODULE__, :tail_task}, task)
              :ok

            {:error, _reason} = error ->
              error
          end
      end
    else
      :error -> {:error, :missing_data_plane_client}
    end
  end

  @impl true
  def unsubscribe(_opts) do
    case Process.delete({__MODULE__, :tail_task}) do
      nil -> :ok
      pid -> Process.exit(pid, :kill) && :ok
    end
  end

  defp invoke(opts, function, args) do
    with {:ok, client} <- Keyword.fetch(opts, :client) do
      client_opts = Keyword.get(opts, :client_opts, [])

      cond do
        client_opts != [] and function_exported?(client, function, length(args) + 1) ->
          apply(client, function, args ++ [client_opts])

        function_exported?(client, function, length(args)) ->
          apply(client, function, args)

        function_exported?(client, function, length(args) + 1) ->
          apply(client, function, args ++ [[]])

        true ->
          {:error, {:invalid_data_plane_client, client, function}}
      end
    else
      :error -> {:error, :missing_data_plane_client}
    end
  end

  defp normalize_stats(stats) when is_map(stats) do
    %{
      total_entries: value(stats, :total_entries, 0),
      total_bytes: value(stats, :total_bytes, 0),
      raw_blocks: value(stats, :raw_blocks, 0),
      raw_bytes: value(stats, :raw_bytes, 0),
      compressed_blocks: value(stats, :compressed_blocks, 0),
      compressed_bytes: value(stats, :compressed_bytes, 0),
      compression_raw_bytes_in: value(stats, :compression_input_bytes_total, 0),
      compression_compressed_bytes_out: value(stats, :compression_output_bytes_total, 0),
      compaction_count: value(stats, :optimize_count, 0),
      oldest_timestamp: value(stats, :oldest_timestamp, nil),
      newest_timestamp: value(stats, :newest_timestamp, nil),
      storage_mode: :libsql
    }
  end

  defp value(map, key, default), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
