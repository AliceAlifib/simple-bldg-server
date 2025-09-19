defmodule BldgServer.GraphStorage do

  def write_items(namespace, entity_type, items) do
    IO.puts("Writing #{length(items)} #{entity_type} items to namespace #{namespace} in dgraph...")
    {:ok, []}
  end
end
