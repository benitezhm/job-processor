defmodule JobProcessor.Error do
  @moduledoc """
  An expected domain error caused by invalid job input.
  """

  @enforce_keys [:code, :message]
  defstruct [:code, :message]

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t()
        }
end
