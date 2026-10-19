defmodule Ep.Auth.Principal do
  @moduledoc "An authenticated session reference, revalidated at each protected operation."
  @enforce_keys [:identity_id, :session_id]
  defstruct [:identity_id, :session_id]
end
