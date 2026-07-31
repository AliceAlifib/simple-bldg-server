defmodule BldgServer.SafeUrlTest do
  @moduledoc """
  SSRF guard. Uses literal IPs (no DNS) and toggles the blocking flag on, since
  the test environment otherwise relaxes it for Bypass mock servers.
  """
  use ExUnit.Case, async: false

  alias BldgServer.SafeUrl

  setup do
    prev = Application.get_env(:bldg_server, :block_private_callback_urls)
    Application.put_env(:bldg_server, :block_private_callback_urls, true)
    on_exit(fn -> Application.put_env(:bldg_server, :block_private_callback_urls, prev) end)
    :ok
  end

  describe "rejected targets (blocking on)" do
    test "cloud metadata / link-local" do
      assert {:error, _} = SafeUrl.validate("http://169.254.169.254/latest/meta-data/")
    end

    test "loopback" do
      assert {:error, _} = SafeUrl.validate("http://127.0.0.1:8080/cb")
      assert {:error, _} = SafeUrl.validate("http://[::1]:8080/cb")
    end

    test "RFC1918 private ranges" do
      assert {:error, _} = SafeUrl.validate("http://10.0.0.5/cb")
      assert {:error, _} = SafeUrl.validate("http://172.16.3.4/cb")
      assert {:error, _} = SafeUrl.validate("http://192.168.1.10/cb")
    end

    test "CGNAT and unspecified" do
      assert {:error, _} = SafeUrl.validate("http://100.64.0.1/cb")
      assert {:error, _} = SafeUrl.validate("http://0.0.0.0/cb")
    end

    test "IPv4-mapped IPv6 loopback is unwrapped and rejected" do
      assert {:error, _} = SafeUrl.validate("http://[::ffff:127.0.0.1]/cb")
    end

    test "non-http(s) schemes" do
      assert {:error, _} = SafeUrl.validate("file:///etc/passwd")
      assert {:error, _} = SafeUrl.validate("gopher://10.0.0.1/")
    end

    test "missing host and non-string" do
      assert {:error, _} = SafeUrl.validate("not a url")
      assert {:error, _} = SafeUrl.validate(nil)
    end
  end

  describe "accepted targets (blocking on)" do
    test "public literal IPs" do
      assert :ok = SafeUrl.validate("http://8.8.8.8/cb")
      assert :ok = SafeUrl.validate("https://1.1.1.1/webhook")
    end

    test "allow-list host bypasses the IP check" do
      System.put_env("BATTERY_URL_ALLOWED_HOSTS", "internal.batteries.example")
      on_exit(fn -> System.delete_env("BATTERY_URL_ALLOWED_HOSTS") end)
      # host is vouched by the operator, so no resolution/IP check is applied
      assert :ok = SafeUrl.validate("https://internal.batteries.example/cb")
    end
  end

  describe "blocking off (dev/test default)" do
    test "loopback is permitted so Bypass mock servers work" do
      Application.put_env(:bldg_server, :block_private_callback_urls, false)
      assert :ok = SafeUrl.validate("http://127.0.0.1:9999/cb")
      # scheme hygiene is still enforced even when blocking is off
      assert {:error, _} = SafeUrl.validate("ftp://127.0.0.1/cb")
    end
  end
end
