defmodule BldgServer.SentryScrubber do
  @moduledoc """
  Sentry `before_send` hook that redacts sensitive fields from events before
  they leave the app, so credentials/PII captured incidentally (request params,
  headers, cookies, extra context) never reach Sentry. Wired in
  config/runtime.exs. Defensive by design — it only touches maps it recognizes
  and passes everything else through unchanged.
  """

  @sensitive ~w(password token session_id callback_url secret authorization cookie email secret_key_base redis_pwd)

  def before_send(%{} = event) do
    event
    |> scrub_field(:extra)
    |> scrub_request()
  end

  def before_send(event), do: event

  defp scrub_field(event, key) do
    case Map.get(event, key) do
      map when is_map(map) -> Map.put(event, key, scrub_map(map))
      _ -> event
    end
  end

  defp scrub_request(event) do
    case Map.get(event, :request) do
      req when is_map(req) ->
        scrubbed =
          req
          |> scrub_nested(:data)
          |> scrub_nested(:headers)
          |> scrub_nested(:cookies)

        Map.put(event, :request, scrubbed)

      _ ->
        event
    end
  end

  defp scrub_nested(map, key) do
    case Map.get(map, key) do
      nested when is_map(nested) -> Map.put(map, key, scrub_map(nested))
      _ -> map
    end
  end

  defp scrub_map(map) do
    Map.new(map, fn {k, v} ->
      if sensitive?(k), do: {k, "[FILTERED]"}, else: {k, v}
    end)
  end

  defp sensitive?(key) do
    normalized = key |> to_string() |> String.downcase()
    Enum.any?(@sensitive, &String.contains?(normalized, &1))
  end
end
