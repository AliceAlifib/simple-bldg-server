defmodule BldgServer.DgraphClient do
  @moduledoc """
  HTTP client for Dgraph using existing Finch instance
  """

  require Logger

  @dgraph_url Application.compile_env(:bldg_server, :dgraph_url, "http://host.docker.internal:8080")
  @mutate_endpoint "#{@dgraph_url}/mutate?commitNow=true"
  @timeout 30_000

  # Public API - uses the existing Finch instance
  def mutate_objects(objects) when is_list(objects) do
    Logger.info("Using #{@dgraph_url}")
    perform_mutation(objects)
  end

  # Private functions
  defp perform_mutation(objects) do
    mutation_data = %{
      "set" => objects
    }

    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    with {:ok, json_body} <- Jason.encode(mutation_data),
         request <- Finch.build(:post, @mutate_endpoint, headers, json_body),
         {:ok, %Finch.Response{status: 200, body: response_body}} <-
           # Use the existing Finch instance (likely named :finch or similar)
           Finch.request(request, FinchClient, receive_timeout: @timeout),
         {:ok, response} <- Jason.decode(response_body) do

      extract_uids(response)
    else
      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("Dgraph returned status #{status}: #{body}")
        {:error, "Dgraph server error (#{status}): #{body}"}

      {:error, %Jason.EncodeError{} = error} ->
        {:error, "JSON encoding failed: #{Exception.message(error)}"}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "JSON decoding failed: #{Exception.message(error)}"}

      {:error, %Finch.Error{} = error} ->
        Logger.error("HTTP request failed: #{Exception.message(error)}")
        {:error, "Connection to Dgraph failed: #{Exception.message(error)}"}

      {:error, reason} ->
        Logger.error("Unexpected error: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end


  defp extract_uids(%{"data" => %{"uids" => uids}}) when is_map(uids) do
    uid_list = Map.values(uids)
    Logger.debug("Extracted #{length(uid_list)} UIDs from mutation response")
    {:ok, uid_list}
  end

  defp extract_uids(%{"data" => data}) do
    Logger.warn("Unexpected response format - no UIDs found: #{inspect(data)}")
    {:ok, []}
  end

  defp extract_uids(response) do
    Logger.warn("Unexpected Dgraph response format: #{inspect(response)}")
    {:ok, []}
  end
end
