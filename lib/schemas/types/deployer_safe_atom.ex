defmodule Deployer.SafeAtom do
  @behaviour Ecto.Type
  def type, do: :string

  def load(data) when is_atom(data), do: {:ok, data}
  def load(data) when is_binary(data), do: {:ok, String.to_existing_atom(data)}
  def load(_), do: :error

  def cast(data) when is_atom(data), do: {:ok, data}
  def cast(data) when is_binary(data), do: {:ok, String.to_existing_atom(data)}
  def cast(_), do: :error

  def dump(data) when is_atom(data) or is_binary(data), do: {:ok, data}
  def dump(_), do: :error
end
