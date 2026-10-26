defmodule Ep.Monitoring.Backup do
  @moduledoc "Local PostgreSQL rehearsal artifacts: snapshot-consistent inventory, authenticated encryption and a signed current erasure ledger."
  import Ecto.Query
  import Bitwise
  alias Ep.Repo

  def capture(output, actor_id \\ nil) do
    verify_client!()
    directory = Path.dirname(Path.expand(output))

    unless File.exists?(directory) do
      File.mkdir_p!(directory)
      File.chmod!(directory, 0o700)
    end

    {:ok, stat} = File.lstat(directory)

    unless stat.type == :directory && band(stat.mode, 0o077) == 0,
      do: raise("Backup directory must be private")

    if File.exists?(output) || File.exists?(output <> ".manifest.json"),
      do: raise("Backup output already exists")

    temporary = Path.join(directory, ".snapshot-" <> Ecto.UUID.generate())

    try do
      {:ok, subjects} =
        Repo.transaction(
          fn ->
            Ecto.Adapters.SQL.query!(
              Repo,
              "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY",
              []
            )

            %{rows: [[snapshot]]} =
              Ecto.Adapters.SQL.query!(Repo, "SELECT pg_export_snapshot()", [])

            subjects =
              Repo.all(from i in Ep.Auth.Identity, select: i.id)
              |> Enum.map(&Ep.Monitoring.Privacy.subject_hash/1)
              |> Enum.sort()

            command!("pg_dump", [
              "--format=custom",
              "--no-password",
              "--snapshot=" <> snapshot,
              "--file=" <> temporary
            ])

            File.chmod!(temporary, 0o600)
            subjects
          end,
          timeout: 120_000
        )

      vault!("encrypt", temporary, output)

      manifest = %{
        "kind" => "monitoring_backup_manifest",
        "backup_id" => Ecto.UUID.generate(),
        "format" => "postgres_custom_aes256gcm_v1",
        "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "subject_hashes" => subjects,
        "coverage" => "registered_identity_superset",
        "dependencies" => [],
        "original_retirement" => "pending_custodian_evidence",
        "sha256" => digest(output)
      }

      write_signed(output <> ".manifest.json", manifest)

      if actor_id do
        {:ok, _} =
          Repo.transaction(fn ->
            cid = Ecto.UUID.generate()

            Ep.Events.append!(
              %{
                scope: "global",
                scope_key: "global",
                stream_type: "monitoring_backup",
                stream_id: manifest["backup_id"],
                actor_identity_id: actor_id,
                command_id: cid,
                correlation_id: cid
              },
              [
                {"MonitoringBackupCaptured",
                 %{
                   "backup_id" => manifest["backup_id"],
                   "subjects" => length(subjects),
                   "sha256" => manifest["sha256"]
                 }}
              ]
            )
          end)
      end

      %{
        backup_id: manifest["backup_id"],
        subjects: length(subjects),
        original_status: "retained_private_original"
      }
    after
      File.rm(temporary)
    end
  end

  def ledger(output) do
    hashes = Repo.all(from e in Ep.Monitoring.Erasure, select: e.subject_hash) |> Enum.sort()

    write_signed(output, %{
      "kind" => "monitoring_erasure_ledger",
      "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "subject_hashes" => hashes
    })

    %{subjects: length(hashes)}
  end

  def restore_local(input, manifest, ledger, sandbox) do
    unless Regex.match?(~r/^sl2030_monitoring_restore_[a-z0-9_]+$/, sandbox),
      do: raise("Restore requires a new named local monitoring sandbox")

    inventory = read_signed(manifest, "monitoring_backup_manifest")
    erasures = read_signed(ledger, "monitoring_erasure_ledger")

    unless inventory["sha256"] == digest(input),
      do: raise("Backup digest does not match its inventory")

    target = connection_env(sandbox)

    unless target["PGHOST"] in ["localhost", "127.0.0.1", "::1"],
      do: raise("Only loopback restore rehearsals are supported")

    plain = Path.join(Path.dirname(input), ".restore-" <> Ecto.UUID.generate())

    try do
      vault!("decrypt", input, plain)
      pg!("createdb", ["--no-password", sandbox], target)

      pg!(
        "pg_restore",
        [
          "--no-password",
          "--exit-on-error",
          "--no-owner",
          "--no-acl",
          "--dbname=" <> sandbox,
          plain
        ],
        target
      )

      # The sandbox remains unpublished. Apply the latest ledger with `apply-ledger` before any reads.
      %{
        sandbox: sandbox,
        erasure_subjects: length(erasures["subject_hashes"]),
        state: "unpublished_awaiting_ledger",
        original_retirement: "pending"
      }
    after
      File.rm(plain)
    end
  end

  def apply_ledger(path) do
    db = connection_env()["PGDATABASE"]

    unless connection_env()["PGHOST"] in ["localhost", "127.0.0.1", "::1"] &&
             Regex.match?(~r/^sl2030_monitoring_restore_[a-z0-9_]+$/, db),
           do: raise("Ledger restoration requires a local monitoring sandbox")

    ledger = read_signed(path, "monitoring_erasure_ledger")

    {:ok, _} =
      Repo.transaction(fn ->
        Enum.each(ledger["subject_hashes"], fn hash ->
          Repo.insert!(%Ep.Monitoring.Erasure{subject_hash: hash, state: "pending"},
            on_conflict: [set: [state: "pending"]],
            conflict_target: :subject_hash
          )
        end)
      end)

    Ep.Monitoring.Privacy.backfill()
    Enum.each(ledger["subject_hashes"], &Ep.Monitoring.Privacy.erase_hash/1)

    %{
      state: "monitoring_sanitized_only",
      domain_review: "required_before_any_publication",
      original_retirement: "still_pending"
    }
  end

  def pending_actions(ledger, manifests) do
    erased = read_signed(ledger, "monitoring_erasure_ledger")["subject_hashes"] |> MapSet.new()

    Enum.flat_map(manifests, fn path ->
      manifest = read_signed(path, "monitoring_backup_manifest")

      affected =
        MapSet.intersection(erased, MapSet.new(manifest["subject_hashes"])) |> MapSet.size()

      if affected > 0,
        do: [
          %{
            backup_id: manifest["backup_id"],
            affected_subjects: affected,
            action: "bring_online_in_isolated_sandbox",
            custodian: "pending_assignment",
            original_retirement: "unresolved",
            dependencies: manifest["dependencies"]
          }
        ],
        else: []
    end)
  end

  def read_signed(path, kind) do
    data = File.read!(path) |> Jason.decode!()
    signature = data["signature"]
    unsigned = Map.delete(data, "signature")

    unless data["kind"] == kind && is_binary(signature) &&
             Plug.Crypto.secure_compare(sign(unsigned), signature),
           do: raise("Invalid signed inventory/ledger")

    unless is_list(data["subject_hashes"]) &&
             Enum.all?(data["subject_hashes"], &Regex.match?(~r/^[0-9a-f]{64}$/, &1)),
           do: raise("Invalid subject inventory")

    unsigned
  end

  defp write_signed(path, data) do
    encoded = Jason.encode!(Map.put(data, "signature", sign(data)))

    case File.open(path, [:write, :exclusive, :binary]) do
      {:ok, file} ->
        File.chmod!(path, 0o600)
        IO.binwrite(file, encoded)
        :file.sync(file)
        File.close(file)

      _ ->
        raise("Refusing to overwrite an inventory/ledger")
    end
  end

  defp sign(data),
    do:
      :crypto.mac(:hmac, :sha256, privacy_key(), "monitoring-backup-v1:" <> Jason.encode!(data))
      |> Base.encode16(case: :lower)

  defp privacy_key,
    do:
      Application.get_env(:ep, :monitoring_privacy_key) ||
        Application.fetch_env!(:ep, EpWeb.Endpoint)[:secret_key_base]

  defp digest(path) do
    File.stream!(path, 65_536, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, ctx ->
      :crypto.hash_update(ctx, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp vault!(operation, input, output) do
    executable = Path.expand("../../../../monitor/bin/backup-vault", __DIR__)
    # Ruby reads the encryption key from the inherited environment, never argv.
    case System.cmd(executable, [operation, input, output], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> raise("Backup encryption/authentication failed")
    end
  end

  defp command!(command, args), do: pg!(command, args, connection_env())

  defp pg!(command, args, env) do
    executable = pg_executable!(command)

    case System.cmd(executable, args, env: Map.to_list(env), stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> raise("PostgreSQL backup/restore operation failed")
    end
  end

  defp pg_executable!(command) do
    candidate =
      case System.get_env("EP_MONITOR_PG_BIN") do
        nil -> command
        directory -> Path.join(directory, command)
      end

    System.find_executable(candidate) || raise("PostgreSQL client tools are required")
  end

  defp verify_client! do
    %{rows: [[version]]} = Ecto.Adapters.SQL.query!(Repo, "SHOW server_version_num", [])
    server_major = div(String.to_integer(version), 10_000)
    {client, 0} = System.cmd(pg_executable!("pg_dump"), ["--version"])
    [_, major] = Regex.run(~r/\(PostgreSQL\) (\d+)/, client)

    unless String.to_integer(major) == server_major,
      do: raise("Use PostgreSQL clients matching the server major; configure EP_MONITOR_PG_BIN")
  end

  defp connection_env(database \\ nil) do
    uri = URI.parse(System.fetch_env!("DATABASE_URL"))
    [username | password] = String.split(uri.userinfo || "", ":", parts: 2)

    %{
      "PGHOST" => uri.host || "localhost",
      "PGPORT" => Integer.to_string(uri.port || 5432),
      "PGUSER" => URI.decode(username),
      "PGDATABASE" => database || URI.decode(String.trim_leading(uri.path || "", "/")),
      "PGPASSWORD" => if(password == [], do: "", else: URI.decode(hd(password)))
    }
  end
end
