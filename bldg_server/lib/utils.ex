defmodule Utils do

  def is_older_than_x_minutes_ago(dt, x), do: NaiveDateTime.diff(NaiveDateTime.utc_now(), dt) > (x * 60)

  def is_newer_than_x_minutes_ago(dt, x), do: NaiveDateTime.diff(NaiveDateTime.utc_now(), dt) < (x * 60)

  def limit_list_to(list, limit) do
    case list do
      nil -> []
      _ -> Enum.take(list, limit)
    end
  end

  @doc """
  Escapes LIKE wildcards in a user-supplied string so it matches literally.

  Floor-subtree queries build a pattern like `"\#{flr}/%"`. Without escaping, a
  `flr` value containing `%` or `_` would act as a wildcard and broaden the
  match to unintended floors/subtrees. Escapes `\\`, `%` and `_` using the
  Postgres default LIKE escape character (backslash). The values are already
  passed as query parameters, so this is scope-narrowing, not SQL-injection
  defense.
  """
  def escape_like_pattern(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

end
