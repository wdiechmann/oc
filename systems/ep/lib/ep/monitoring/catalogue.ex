defmodule Ep.Monitoring.Catalogue do
  @moduledoc "Versioned, safe observation vocabulary. Arbitrary diagnostic text is not accepted."
  @entries %{
    "database.unavailable" =>
      {"error", "infrastructure", "failed", "The database is unavailable."},
    "database.saturated" =>
      {"warning", "infrastructure", "pending", "Database pool waiting time is above its limit."},
    "request.error_rate" =>
      {"error", "code", "failed", "Unexpected request failures exceeded the threshold."},
    "request.latency_high" =>
      {"warning", "infrastructure", "pending", "Request latency exceeded the threshold."},
    "application.exception" =>
      {"error", "code", "failed", "The application could not complete its response."},
    "application.contract_invalid" =>
      {"error", "integration", "failed", "An application response did not match its contract."},
    "request.validation_rejected" =>
      {"info", "input", "rejected", "The request needs correction."},
    "request.permission_denied" =>
      {"info", "input", "rejected", "The operation is not permitted."},
    "request.conflict" =>
      {"info", "input", "rejected", "The request conflicts with current state."},
    "dependency.unavailable" =>
      {"error", "infrastructure", "failed", "A required service is unavailable."},
    "projection.delayed" => {"warning", "projection", "pending", "The view is still updating."},
    "job.exhausted" =>
      {"error", "job", "failed", "Background processing needs operator attention."},
    "delivery.attempted" =>
      {"info", "delivery", "pending", "The application attempted delivery."},
    "delivery.provider_accepted" =>
      {"info", "delivery", "accepted",
       "The provider accepted the message; delivery is not confirmed."},
    "delivery.delivered" => {"info", "delivery", "accepted", "The provider reported delivery."},
    "delivery.bounced" =>
      {"warning", "delivery", "failed", "The provider reported a delivery failure."},
    "delivery.rejected" =>
      {"warning", "delivery", "failed", "The provider rejected the message."},
    "delivery.unknown" =>
      {"warning", "delivery", "unknown",
       "The delivery result is unknown; reconcile before retrying."},
    "condition.recovered" =>
      {"info", "infrastructure", "accepted", "The source reported recovery."}
  }
  def entries,
    do:
      Map.new(@entries, fn {code, {severity, category, outcome, message}} ->
        {code, %{severity: severity, category: category, outcome: outcome, safe_message: message}}
      end)

  def fetch(code), do: Map.fetch(entries(), code)
end
