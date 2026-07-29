defmodule BldgServer.BatteryCredentialTest do
  use BldgServer.DataCase

  alias BldgServer.Batteries

  describe "provision_battery_credential/2 and authenticate_battery_key/1" do
    test "provisions a key whose hash authenticates back to the credential" do
      assert {:ok, key, cred} =
               Batteries.provision_battery_credential("file-system-battery", "owner@example.com")

      assert is_binary(key) and byte_size(key) > 20
      assert cred.battery_type == "file-system-battery"
      assert cred.owner_email == "owner@example.com"
      # the plaintext key is not stored
      refute cred.api_key_hash == key

      found = Batteries.authenticate_battery_key(key)
      assert found.id == cred.id
    end

    test "a wrong or non-string key does not authenticate" do
      {:ok, _key, _cred} =
        Batteries.provision_battery_credential("fsb", "owner@example.com")

      assert Batteries.authenticate_battery_key("wrong-key") == nil
      assert Batteries.authenticate_battery_key(nil) == nil
    end
  end
end
