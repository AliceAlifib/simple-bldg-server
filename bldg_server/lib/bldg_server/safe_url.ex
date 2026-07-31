defmodule BldgServer.SafeUrl do
  @moduledoc """
  SSRF guard for outbound URLs the server is asked to call (battery webhook
  `callback_url`s). The server fetches these URLs, so an attacker who can set one
  could otherwise point it at internal services or the cloud metadata endpoint
  (`169.254.169.254`).

  `validate/1` accepts only `http`/`https` URLs whose host resolves entirely to
  public IP addresses, rejecting loopback, link-local (incl. IMDS), private
  (RFC1918 / CGNAT / unique-local), multicast and reserved ranges. It resolves
  the host so a public name pointing at a private IP is still rejected. A DNS
  name can still rebind between validation and the actual request (TOCTOU), so
  callers validate again at request time as defense-in-depth.

  A host listed in the `BATTERY_URL_ALLOWED_HOSTS` env var (comma-separated) is
  treated as operator-vouched and accepted without the IP-range check — the
  prod escape hatch for a legitimate internal battery.

  The private/loopback IP rejection is gated by the
  `:block_private_callback_urls` app-env flag (true in prod; false in dev/test,
  where Bypass mock servers and local batteries run on loopback). Scheme and
  host hygiene is always enforced.
  """

  @schemes ~w(http https)

  @spec validate(term()) :: :ok | {:error, String.t()}
  def validate(url) when is_binary(url) do
    uri = URI.parse(url)

    with :ok <- check_scheme(uri),
         {:ok, host} <- check_host(uri) do
      cond do
        host in allowed_hosts() -> :ok
        not block_private?() -> :ok
        true -> resolve_and_check(host)
      end
    end
  end

  def validate(_), do: {:error, "callback_url must be a string"}

  defp block_private?, do: Application.get_env(:bldg_server, :block_private_callback_urls, true)

  defp resolve_and_check(host) do
    with {:ok, ips} <- resolve(host) do
      check_ips(ips)
    end
  end

  defp check_scheme(%URI{scheme: scheme}) when scheme in @schemes, do: :ok
  defp check_scheme(%URI{scheme: scheme}), do: {:error, "unsupported URL scheme: #{inspect(scheme)}"}

  defp check_host(%URI{host: host}) when is_binary(host) and host != "", do: {:ok, host}
  defp check_host(_), do: {:error, "URL has no host"}

  defp allowed_hosts do
    case System.get_env("BATTERY_URL_ALLOWED_HOSTS") do
      nil -> []
      "" -> []
      value -> value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  # Resolve to IPs. A literal IP address resolves to itself; a name is looked up
  # over both IPv4 and IPv6 so neither family can smuggle a private target.
  defp resolve(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, ip} ->
        {:ok, [ip]}

      {:error, _} ->
        v4 = case :inet.getaddrs(charlist, :inet) do
          {:ok, ips} -> ips
          _ -> []
        end

        v6 = case :inet.getaddrs(charlist, :inet6) do
          {:ok, ips} -> ips
          _ -> []
        end

        case v4 ++ v6 do
          [] -> {:error, "could not resolve host"}
          ips -> {:ok, ips}
        end
    end
  end

  defp check_ips(ips) do
    if Enum.all?(ips, &public_ip?/1),
      do: :ok,
      else: {:error, "URL resolves to a private, loopback, or link-local address"}
  end

  @doc false
  # IPv4
  def public_ip?({a, b, _c, _d} = ip) when tuple_size(ip) == 4 do
    cond do
      a == 0 -> false
      a == 10 -> false
      a == 127 -> false
      a == 169 and b == 254 -> false
      a == 172 and b in 16..31 -> false
      a == 192 and b == 168 -> false
      a == 100 and b in 64..127 -> false
      a == 198 and b in 18..19 -> false
      a == 192 and b == 0 -> false
      a >= 224 -> false
      true -> true
    end
  end

  # IPv6
  def public_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: false
  def public_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: false
  # IPv4-mapped ::ffff:a.b.c.d — unwrap and apply the IPv4 rules.
  def public_ip?({0, 0, 0, 0, 0, 0xffff, g, h}) do
    public_ip?({div(g, 256), rem(g, 256), div(h, 256), rem(h, 256)})
  end

  def public_ip?({first, _, _, _, _, _, _, _} = ip) when tuple_size(ip) == 8 do
    high = Bitwise.bsr(first, 8)

    cond do
      # fc00::/7 unique-local (high byte 0xfc or 0xfd)
      high in [0xFC, 0xFD] -> false
      # fe80::/10 link-local
      Bitwise.band(first, 0xFFC0) == 0xFE80 -> false
      # ff00::/8 multicast
      high == 0xFF -> false
      true -> true
    end
  end
end
