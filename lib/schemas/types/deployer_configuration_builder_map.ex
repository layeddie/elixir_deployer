defmodule Deployer.Configuration.BuilderMap do
  @behaviour Ecto.Type
  def type, do: :map

  require Deployer.Helpers.ANSI

  alias Deployer.Configuration.{Builder, Context}

  def load(data) when is_map(data) do
    data_map =
      Enum.reduce(data, %{}, fn
        ({k, %Builder{} = builder}, acc) -> Map.put(acc, k, builder)
        ({k, builder}, acc) when is_map(builder) ->
          case Context.create_builder(builder) do
            {:ok, valid} -> Map.put(acc, k, valid)
            _ ->
              Deployer.Helpers.ANSI.warn("Invalid Builder Definition - for key #{k} - #{inspect builder}")
              acc
          end
          ({k, builder}, acc) ->
          Deployer.Helpers.ANSI.warn("Invalid Builder Definition - for key #{k} - #{inspect builder}")
          acc
      end)

    {:ok, data_map}
  end

  def load(_), do: :error

  def cast(data) when is_map(data) do
    data_map =
      Enum.reduce(data, %{}, fn
        ({k, %Builder{} = builder}, acc) -> Map.put(acc, k, builder)
        ({k, builder}, acc) when is_map(builder) ->
          case Context.create_builder(builder) do
            {:ok, valid} -> Map.put(acc, k, valid)
            _ ->
              Deployer.Helpers.ANSI.warn("Invalid Builder Definition - for key #{k} - #{inspect builder}")
              acc
          end
          ({k, builder}, acc) ->
          Deployer.Helpers.ANSI.warn("Invalid Builder Definition - for key #{k} - #{inspect builder}")
          acc
      end)

    {:ok, data_map}
  end

  def cast(_), do: :error

  def dump(data) when is_map(data), do: {:ok, data}
  def dump(_), do: :error
end
