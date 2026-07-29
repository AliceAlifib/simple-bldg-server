defmodule BldgServer.Token do
  @moduledoc """
  Handles creating and validating tokens.
  """

    alias BldgServer.Residents.Resident

  # Salts are sourced from the environment (config/runtime.exs). They namespace
  # the Phoenix.Token signing key derived from SECRET_KEY_BASE; keeping the
  # magic-link and bearer salts distinct prevents a token minted for one purpose
  # from verifying for the other.
  defp magic_link_salt, do: Application.fetch_env!(:bldg_server, :magic_link_salt)
  defp auth_token_salt, do: Application.fetch_env!(:bldg_server, :auth_token_salt)

  # Magic-link email-verification token (carries the session_id).
  def generate_login_token(session_id) do
    Phoenix.Token.sign(BldgServerWeb.Endpoint, magic_link_salt(), session_id)
  end

  def verify_login_token(token) do
    max_age = 86_400 # tokens that are older than a day should be invalid
    Phoenix.Token.verify(BldgServerWeb.Endpoint, magic_link_salt(), token, max_age: max_age)
  end

  # Resident bearer token (Tranche 2 API/WS credential). Carries the
  # resident_id + session_id so the auth plug can bind the token to a VERIFIED
  # session row (the sessions table is the revocation list). 7-day max age
  # matches the week-long session-reuse window in Residents.login/2.
  @auth_token_max_age 604_800

  def generate_auth_token(resident_id, session_id) do
    Phoenix.Token.sign(BldgServerWeb.Endpoint, auth_token_salt(), %{
      resident_id: resident_id,
      session_id: session_id
    })
  end

  def verify_auth_token(token) do
    Phoenix.Token.verify(BldgServerWeb.Endpoint, auth_token_salt(), token,
      max_age: @auth_token_max_age
    )
  end
end