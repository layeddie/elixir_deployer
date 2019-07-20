defmodule Deployer.Configuration.GroupMap do
  @behaviour Ecto.Type
  def type, do: :map
  
  require Deployer.Helpers.ANSI

  alias Deployer.Configuration.{Group, Context}

  def load(data) when is_map(data) do
    data_map =
      Enum.reduce(data, %{}, fn
        ({k, %Group{} = group}, acc) -> Map.put(acc, k, group)
        ({k, group}, acc) when is_map(group) ->
          case Context.create_group(group) do
            {:ok, valid} -> Map.put(acc, k, valid)
            _ ->
              Deployer.Helpers.ANSI.warn("Invalid Group Definition - for key #{k} - #{inspect group}")
              acc
          end
          ({k, group}, acc) ->
          Deployer.Helpers.ANSI.warn("Invalid Group Definition - for key #{k} - #{inspect group}")
          acc
      end)

    {:ok, data_map}
  end

  def load(_), do: :error

  def cast(data) when is_map(data) do
    data_map =
      Enum.reduce(data, %{}, fn
        ({k, %Group{} = group}, acc) -> Map.put(acc, k, group)
        ({k, group}, acc) when is_map(group) ->
          case Context.create_group(group) do
            {:ok, valid} -> Map.put(acc, k, valid)
            _ ->
              Deployer.Helpers.ANSI.warn("Invalid Group Definition - for key #{k} - #{inspect group}")
              acc
          end
          ({k, group}, acc) ->
          Deployer.Helpers.ANSI.warn("Invalid Group Definition - for key #{k} - #{inspect group}")
          acc
      end)

    {:ok, data_map}
  end

  def cast(_), do: :error

  def dump(data) when is_map(data), do: {:ok, data}
  def dump(_), do: :error
end
