defmodule Ep.Monitoring.Spool do
  @moduledoc "Private encrypted transport files compatible with the independent Ruby collector."
  use GenServer
  require Logger
  import Bitwise
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def enqueue(input) do
    case Process.whereis(__MODULE__) do
      nil ->
        unavailable()

      pid ->
        if elem(Process.info(pid, :message_queue_len), 1) < 100 do
          try do
            GenServer.call(pid, {:enqueue, input}, 500)
          catch
            :exit, _ -> unavailable()
          end
        else
          unavailable()
        end
    end
  end

  defp unavailable, do: Logger.warning("monitoring_spool_unavailable")
  @impl true
  def init(_), do: {:ok, %{}}
  @impl true
  def handle_call({:enqueue, input}, _, state) do
    result =
      try do
        dir = Application.get_env(:ep, :monitoring_spool_dir)
        key = Application.get_env(:ep, :monitoring_spool_key)

        if is_binary(dir) && is_binary(key) do
          raw_key = Base.decode64!(key)
          true = byte_size(raw_key) == 32

          unless File.exists?(dir) do
            File.mkdir_p!(dir)
            File.chmod!(dir, 0o700)
          end

          {:ok, stat} = File.lstat(dir)
          true = stat.type == :directory && band(stat.mode, 0o077) == 0
          files = Path.wildcard(Path.join(dir, "*.{pending,inflight,quarantine}"))
          bytes = Enum.reduce(files, 0, fn f, n -> n + File.stat!(f).size end)

          if length(files) >= 10_000 || bytes >= 64 * 1024 * 1024 do
            Logger.error("monitoring_spool_full")
            :full
          else
            nonce = :crypto.strong_rand_bytes(12)

            payload =
              Jason.encode!(%{
                created_at: System.system_time(:second),
                body: %{observation: input, delivery: false}
              })

            {ciphertext, tag} =
              :crypto.crypto_one_time_aead(
                :aes_256_gcm,
                raw_key,
                nonce,
                payload,
                "ep-monitor-spool-v1",
                true
              )

            encoded =
              Jason.encode!(%{
                v: 1,
                nonce: Base.encode64(nonce),
                tag: Base.encode64(tag),
                data: Base.encode64(ciphertext)
              })

            id = input["source_observation_id"]
            {:ok, _} = Ecto.UUID.cast(id)
            temp = Path.join(dir, ".tmp-" <> Ecto.UUID.generate())
            File.write!(temp, encoded, [:exclusive, :binary, :sync])
            File.chmod!(temp, 0o600)
            File.rename!(temp, Path.join(dir, id <> ".pending"))
            :ok
          end
        else
          Logger.warning("monitoring_spool_unconfigured")
          :unconfigured
        end
      rescue
        _ ->
          unavailable()
          :error
      end

    {:reply, result, state}
  end
end
