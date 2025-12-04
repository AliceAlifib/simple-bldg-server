defmodule BldgServerWeb.StagingController do
  use BldgServerWeb, :controller

  alias BldgServer.DgraphClient

  require Logger

  def write_data(conn, %{"storage_type"  => "dgraph", "namespace"  => namespace, "entity_type"  => entity_type, "items" => items}) when is_list(items) do
    # add the dgraph.type attribute to all items
    enriched_items = Enum.map(items, fn item ->
      Map.put(item, "dgraph.type", entity_type)
    end)
    # Validate objects before sending to Dgraph
    case validate_objects(enriched_items) do
      :ok ->
        perform_mutation(conn, enriched_items)

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          success: false,
          error: "Validation failed: #{reason}"
        })
    end

  end

  def create_objects(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      error: "Invalid request format. Expected storage_type=dgraph, string entity_type & items array in request body."
    })
  end

  defp perform_mutation(conn, objects) do
    start_time = System.monotonic_time(:millisecond)

    case DgraphClient.mutate_objects(objects) do
      {:ok, uids} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.info("Dgraph mutation completed in #{duration}ms, created #{length(uids)} objects")

        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          keys: uids,
          count: length(uids),
          duration_ms: duration
        })

      {:error, reason} ->
        Logger.error("Dgraph mutation failed: #{reason}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: reason
        })
    end
  end

  defp validate_objects(objects) do
    cond do
      length(objects) == 0 ->
        {:error, "Empty objects array"}

      length(objects) > 10_000 ->
        {:error, "Too many objects (max 10,000 per request)"}

      not Enum.all?(objects, &is_map/1) ->
        {:error, "All objects must be JSON objects"}

      not Enum.all?(objects, &Map.has_key?(&1, "dgraph.type")) ->
        {:error, "All objects must have the dgraph.type attribute"}

      true ->
        validate_object_size(objects)
    end
  end

  defp validate_object_size(objects) do
    # Check if any individual object is too large
    oversized = Enum.find(objects, fn obj ->
      case Jason.encode(obj) do
        {:ok, json} -> byte_size(json) > 1_000_000  # 1MB limit per object
        _ -> false
      end
    end)

    case oversized do
      nil -> :ok
      _ -> {:error, "Individual object too large (max 1MB per object)"}
    end
  end

end
