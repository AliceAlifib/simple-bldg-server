defmodule BldgServer.Address do
  @moduledoc """
  A parsed, structured view of the hierarchical address grammar
  (`g/b(3,2)/l0/b(1,1)`).

  Today the same address-shape assumptions are re-implemented across the
  codebase as ad-hoc string slicing (`extract_coords`, `get_container`,
  `extract_flr_level`, two `calculate_nesting_depth`s, the floor-membership
  queries, the ancestor-broadcast walk). This module is the single place that
  knows the grammar: parse a string once, operate on the struct, render back to
  a string only for storage/wire.

  ## Grammar

    * `g`        — the ground root            -> `:ground`
    * `b(x,y)`   — a bldg at integer coords   -> `{:bldg, x, y}` (x, y may be negative)
    * `l<n>`     — a floor (level n >= 0)      -> `{:floor, n}`
    * anything else (a name alias in a bldg_url, e.g. `team`) -> `{:named, s}`

  Parsing is **total**: any non-empty, `/`-delimited string parses, because
  `bldg_url`s carry name segments that are not coordinate tuples. Round-trip
  holds for every parseable string: `to_string(parse!(s)) == s`.
  """

  defstruct segments: []

  @type segment :: :ground | {:bldg, integer, integer} | {:floor, non_neg_integer} | {:named, String.t()}
  @type t :: %__MODULE__{segments: [segment]}

  @delimiter "/"
  @bldg_re ~r/^b\((-?\d+),(-?\d+)\)$/
  @floor_re ~r/^l(\d+)$/

  @doc "Parse an address string. Returns `{:error, :empty}` for a blank string."
  @spec parse(String.t()) :: {:ok, t} | {:error, :empty}
  def parse(str) when is_binary(str) do
    case String.split(str, @delimiter) do
      [""] -> {:error, :empty}
      segments -> {:ok, %__MODULE__{segments: Enum.map(segments, &parse_segment/1)}}
    end
  end

  @doc "Parse an address string, raising on a blank string."
  @spec parse!(String.t()) :: t
  def parse!(str) do
    case parse(str) do
      {:ok, addr} -> addr
      {:error, reason} -> raise ArgumentError, "invalid address #{inspect(str)}: #{reason}"
    end
  end

  defp parse_segment("g"), do: :ground

  defp parse_segment(seg) do
    cond do
      caps = Regex.run(@bldg_re, seg) -> [_, x, y] = caps; {:bldg, String.to_integer(x), String.to_integer(y)}
      caps = Regex.run(@floor_re, seg) -> [_, n] = caps; {:floor, String.to_integer(n)}
      true -> {:named, seg}
    end
  end

  @doc "Render an address back to its canonical string form."
  @spec to_string(t) :: String.t()
  def to_string(%__MODULE__{segments: segments}) do
    segments |> Enum.map(&segment_to_string/1) |> Enum.join(@delimiter)
  end

  defp segment_to_string(:ground), do: "g"
  defp segment_to_string({:bldg, x, y}), do: "b(#{x},#{y})"
  defp segment_to_string({:floor, n}), do: "l#{n}"
  defp segment_to_string({:named, s}), do: s

  @doc "The last segment of the address."
  @spec last_segment(t) :: segment | nil
  def last_segment(%__MODULE__{segments: []}), do: nil
  def last_segment(%__MODULE__{segments: segments}), do: List.last(segments)

  @doc "The {x, y} coords if the address ends in a bldg segment, else `:error`."
  @spec coords(t) :: {integer, integer} | :error
  def coords(%__MODULE__{} = addr) do
    case last_segment(addr) do
      {:bldg, x, y} -> {x, y}
      _ -> :error
    end
  end

  @doc "The containing address (drops the last segment), or `:error` if there is none."
  @spec container(t) :: t | :error
  def container(%__MODULE__{segments: segments}) when length(segments) <= 1, do: :error
  def container(%__MODULE__{segments: segments}) do
    %__MODULE__{segments: Enum.drop(segments, -1)}
  end

  @doc """
  The floor level: 0 for the ground root, `n` for a `l<n>`-terminated address,
  else `:error`.
  """
  @spec floor_level(t) :: non_neg_integer | :error
  def floor_level(%__MODULE__{segments: [:ground]}), do: 0
  def floor_level(%__MODULE__{} = addr) do
    case last_segment(addr) do
      {:floor, n} -> n
      _ -> :error
    end
  end

  @doc """
  The canonical (bldg) nesting depth: `trunc((segment_count - 1) / 2)`. This is
  the value `Buildings.calculate_nesting_depth/1` computes for a bldg's own
  address (ground-level bldg = 0). The resident "inside" depth is this plus one
  on a bldg-terminated address — see `inside_depth/1`.
  """
  @spec nesting_depth(t) :: non_neg_integer
  def nesting_depth(%__MODULE__{segments: segments}) do
    trunc((length(segments) - 1) / 2)
  end

  @doc """
  The depth a resident standing *inside* this address occupies:
  `trunc(segment_count / 2)`, matching `Residents.calculate_nesting_depth_from_
  address/1`. On a coord address this is `nesting_depth/1 + 1` for a bldg-
  terminated address and equal otherwise — but the canonical definition is
  count-based (it does not depend on the last segment's kind, so a name-aliased
  even-length address like `g/team` is depth 1, not 0).
  """
  @spec inside_depth(t) :: non_neg_integer
  def inside_depth(%__MODULE__{segments: segments}) do
    trunc(length(segments) / 2)
  end

  @doc "True if this is the bare ground root."
  @spec ground?(t) :: boolean
  def ground?(%__MODULE__{segments: [:ground]}), do: true
  def ground?(%__MODULE__{}), do: false

  @doc "True if the address terminates in a bldg segment."
  @spec ends_in_bldg?(t) :: boolean
  def ends_in_bldg?(%__MODULE__{} = addr) do
    match?({:bldg, _, _}, last_segment(addr))
  end

  @doc "True if `maybe_ancestor` is a strict ancestor (prefix) of `addr`."
  @spec ancestor?(t, t) :: boolean
  def ancestor?(%__MODULE__{segments: anc}, %__MODULE__{segments: segs}) do
    length(anc) < length(segs) and List.starts_with?(segs, anc)
  end

  @doc """
  Rewrite `addr` so the subtree rooted at `from` is re-rooted at `to`. Requires
  `from` to equal `addr` or be an ancestor of it; returns `:error` otherwise.

  This is the primitive for safe container relocation: every descendant `d` of a
  moved container gets `rebase(d, old_root, new_root)`.

      iex> rebase(parse!("g/b(5,5)/l0/b(1,1)"), parse!("g/b(5,5)"), parse!("g/b(9,9)"))
      #=> parse!("g/b(9,9)/l0/b(1,1)")
  """
  @spec rebase(t, t, t) :: t | :error
  def rebase(%__MODULE__{segments: segs}, %__MODULE__{segments: from}, %__MODULE__{segments: to}) do
    if List.starts_with?(segs, from) do
      %__MODULE__{segments: to ++ Enum.drop(segs, length(from))}
    else
      :error
    end
  end

  defimpl String.Chars do
    def to_string(addr), do: BldgServer.Address.to_string(addr)
  end
end
