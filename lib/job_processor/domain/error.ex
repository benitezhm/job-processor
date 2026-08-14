defmodule JobProcessor.Error do
  @moduledoc """
  An expected domain error caused by invalid job input.
  """

  @enforce_keys [:code, :message]
  defstruct [:code, :message]

  @type code ::
          :invalid_request
          | :invalid_task
          | :duplicate_task
          | :duplicate_dependency
          | :unknown_dependency
          | :cyclic_dependency

  @type t :: %__MODULE__{
          code: code(),
          message: String.t()
        }
end
