defmodule BldgServerWeb.StagingController do
  use BldgServerWeb, :controller

  alias BldgServer.GraphStorage

  def write_data(conn, %{"namespace"  => namespace, "storage_type"  => storage_type, "entity_type"  => entity_type, "items" => items}) do
    case storage_type do
      "dgraph" ->
        with {:ok, keys} <- GraphStorage.write_items(namespace, entity_type, items) do
          json(conn, %{keys: keys})
        end
      _ ->
        raise "Sorry, #{storage_type} is not supported as staging storage type"
    end

  end

end
