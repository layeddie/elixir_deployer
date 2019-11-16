defmodule Deployer.Configuration.BuilderMap do
  @behaviour Ecto.Type
  def type, do: :map

  require Deployer.Helpers.ANSI

  alias Deployer.Configuration.{Builder, Context}

  def load(data) when is_map(data) do
    data_map =
      Enum.reduce(data, %{}, fn
        ({k, {_,_,_} = mfa}, acc) -> Map.put(acc, k, mfa)
        ({k, builder}, acc) ->
            Deployer.Helpers.ANSI.warn("Invalid Builder Definition when loading, for key #{k} - expected {m, f, a} got #{inspect builder}")
            acc
      end)
    
    {:ok, data_map}
  end

  def load(_), do: :error

  def cast(data) when is_map(data) do
    data_map =
      Enum.reduce(data, %{}, fn
        ({k, {_,_,_} = mfa}, acc) -> Map.put(acc, k, mfa)
        ({k, builder}, acc) ->
          Deployer.Helpers.ANSI.warn("Invalid Builder Definition when casting - for key #{k} - expected {m, f, a} got #{inspect builder}")
          acc
      end)

    {:ok, data_map}
  end

  def cast(_), do: :error

  def dump(_), do: :error
end
