defmodule BldgServer.Email do
  @moduledoc """
  Email notifications definitions
  """

  use Bamboo.Phoenix, view: BldgServer.EmailView

  @reply_to "hello@fromteal.app"
  @from "hello@fromteal.app"


  def login_verification_email(email_address, verification_url) do
    base_email()
    |> to(email_address)
    |> subject("fromTeal login verification")
    |> text_body("Hi, please click on the following link to verify your email address: #{verification_url}")
  end

  def login_verification_html_email(email_address, verification_url) do
    login_verification_email(email_address, verification_url)
    |> html_body("<p><strong>Hi!<strong><p><br> <p>Please <a href=#{verification_url}>click here</a> to verify your email address.</p><br/><br/><p>See you in fromTeal!</p>")
  end

  # TODO use views (see https://phoenixframework.readme.io/docs/sending-email)


  defp base_email() do
    new_email()
    |> put_header("Reply-To", @reply_to)
    |> from(@from)
  end
end
