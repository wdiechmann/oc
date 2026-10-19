defmodule Ep.Support.MagicLinkDelivery do
  @moduledoc false
  def deliver(email, token) do
    send(self(), {:magic_link, email, token})
    :ok
  end
end
