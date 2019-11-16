defmodule Deployer.Configuration.TargetMap do
  @behaviour Ecto.Type
  def type, do: :map

  require Deployer.Helpers.ANSI

  alias Deployer.Configuration.{Target, Context}

  def load(data) when is_map(data) do
    data_map =
      Enum.reduce(data, %{}, fn
        ({k, %Target{} = target}, acc) -> Map.put(acc, k, target)
        ({k, {_,_,_} = mfa}, acc) -> Map.put(acc, k, mfa)
        ({k, target}, acc) when is_map(target) ->
          
          case Context.create_target(target) do
            {:ok, valid} -> Map.put(acc, k, valid)
            {:error, errors} ->
              Deployer.Helpers.ANSI.warn("Invalid Target Definition - loading ctx create - for key #{k} - #{inspect target}\n Errors: #{inspect errors}")
              acc
          end
          
        ({k, target}, acc) ->
            Deployer.Helpers.ANSI.warn("Invalid Target Definition - loading - for key #{k} - #{inspect target}")
            acc
      end)

    {:ok, data_map}
  end

  def load(_), do: :error

  def cast(data) when is_map(data) do
    data_map =
      Enum.reduce(data, %{}, fn
        ({k, %Target{} = target}, acc) -> Map.put(acc, k, target)
        ({k, {_,_,_} = mfa}, acc) -> Map.put(acc, k, mfa)
        ({k, target}, acc) when is_map(target) ->
          case Context.create_target(target) do
            {:ok, valid} -> Map.put(acc, k, valid)
            {:error, errors} ->
              Deployer.Helpers.ANSI.warn("Invalid Target Definition - casting ctx create - for key #{k} - #{inspect target}\n Errors: #{inspect errors}")
              acc
          end

        ({k, target}, acc) ->
          Deployer.Helpers.ANSI.warn("Invalid Target Definition - casting - for key #{k} - #{inspect target}")
          acc
      end)

    {:ok, data_map}
  end

  def cast(_), do: :error

  def dump(data) when is_map(data), do: {:ok, data}
  def dump(_), do: :error
end
