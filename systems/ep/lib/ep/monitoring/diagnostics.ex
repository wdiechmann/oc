defmodule Ep.Monitoring.Diagnostics do
  @moduledoc "Bounded structured diagnostics, never raw exception messages/arguments or full paths."
  alias Ep.{Monitoring, Repo}
  def validate(nil), do: :ok

  def validate(value) when is_map(value) do
    valid =
      Enum.sort(Map.keys(value)) == ~w(exception_class frames) &&
        token?(value["exception_class"], 128) &&
        is_list(value["frames"]) && length(value["frames"]) <= 10 &&
        Enum.all?(value["frames"], &frame?/1)

    if valid, do: :ok, else: {:error, :invalid_observation}
  end

  def validate(_), do: {:error, :invalid_observation}

  defp frame?(frame) when is_map(frame) do
    Enum.sort(Map.keys(frame)) == ~w(file label line) && token?(frame["file"], 120) &&
      token?(frame["label"], 120) &&
      is_integer(frame["line"]) && frame["line"] in 0..10_000_000
  end

  defp frame?(_), do: false

  defp token?(value, max) when is_binary(value),
    do: byte_size(value) in 1..max && Regex.match?(~r/^[A-Za-z0-9_.:?!-]+$/, value)

  defp token?(_, _), do: false

  def read(principal, tid, id) do
    with {:ok, id} <- Monitoring.uuid(id) do
      Repo.transaction(fn ->
        Ep.Monitoring.Privacy.serving!()
        event = Repo.get(Ep.Events.Event, id) || Repo.rollback(:not_found)

        unless event.tenant_id == tid && event.stream_type == "monitoring_issue",
          do: Repo.rollback(:not_found)

        Ep.Monitoring.Access.diagnostic!(principal, tid, event.occasion_id)
        row = Repo.get(Ep.Monitoring.Diagnostic, id) || Repo.rollback(:not_found)
        cutoff = DateTime.add(DateTime.utc_now(), -30 * 86_400, :second)

        unless DateTime.compare(row.inserted_at, cutoff) == :gt &&
                 !Repo.get(Ep.Monitoring.Redaction, id) && !Ep.Monitoring.Privacy.erased?(id),
               do: Repo.rollback(:not_found)

        %{event_id: id, diagnostic: row.payload}
      end)
    else
      _ -> {:error, :not_found}
    end
  end
end
