defmodule Utils do

  def is_older_than_x_minutes_ago(dt, x), do: NaiveDateTime.diff(NaiveDateTime.utc_now(), dt) > (x * 60)

  def is_newer_than_x_minutes_ago(dt, x), do: NaiveDateTime.diff(NaiveDateTime.utc_now(), dt) < (x * 60)

  def limit_list_to(list, limit) do
    case list do
      nil -> []
      _ -> Enum.take(list, limit)
    end
  end

end
