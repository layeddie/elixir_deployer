defmodule Deployer.Helpers do
  require Logger

  alias Deployer.ENV, as: ENV

  def env_from_args(entries, acc)
  def env_from_args([], %ENV{} = acc), do: acc

  def env_from_args([entry | t], %ENV{env: acc} = env) when is_binary(entry) do
    arg_value =
      case entry do
        <<"--", arg_and_value::binary>> -> arg_and_value
        <<"-", arg_and_value::binary>> -> arg_and_value
        arg_and_value -> arg_and_value
      end
    
    n_acc =
      case String.split(arg_value, "=") do
        [arg, <<>>] -> Map.put(acc, String.to_atom(arg), true)
        [<<>> | _] -> acc
        [arg, value] -> Map.put(acc, String.to_atom(arg), value)
        [arg] -> Map.put(acc, String.to_atom(arg), true)
      end
    
    env_from_args(t, %ENV{env | env: n_acc})
  end

  def env_from_args([{arg, value} | t], %ENV{env: acc} = env) when is_atom(arg) do
    n_acc = Map.put(acc, arg, value)
    env_from_args(t, %ENV{env | env: n_acc})
  end

  def env_from_args([{arg, value} | t], %ENV{env: acc} = env) when is_binary(arg) do
    n_acc = Map.put(acc, String.to_atom(arg), value)
    env_from_args(t, %ENV{env | env: n_acc})
  end

  def env_from_args([arg | t], %ENV{} = env) do
    Logger.warn("Invalid argument passed #{inspect arg}")
    env_from_args(t, env)
  end

  def put_env(%ENV{env: env} = full, arg, val) do
    %{full | env: Map.put(env, arg, val)}
  end

  def read_env(%ENV{env: env}, arg, default \\ nil) do
    case Map.fetch(env, arg) do
      {:ok, val} -> val
      _ -> default
    end
  end
  
  def args_into_pterms([]), do: :ok
  
  def args_into_pterms([entry | t]) when is_binary(entry) do
    arg_value = case entry do
                  <<"--", arg_and_value::binary>> -> arg_and_value
                  <<"-", arg_and_value::binary>> -> arg_and_value
                  arg_and_value -> arg_and_value
                end
    
    case String.split(arg_value, "=") do
      [arg, <<>>] -> put_env(String.to_atom(arg), true)
      [<<>> | _] -> :noop
      [arg, value] -> put_env(String.to_atom(arg), value)
      [arg] -> put_env(String.to_atom(arg), true)
    end
    args_into_pterms(t)
  end

  def args_into_pterms([{arg, value} | t]) when is_atom(arg) do
    put_env(arg, value)
    args_into_pterms(t)
  end

  def args_into_pterms([{arg, value} | t]) when is_binary(arg) do
    put_env(String.to_atom(arg), value)
    args_into_pterms(t)
  end

  def args_into_pterms([arg | t]) do
    Logger.warn("Invalid argument passed #{inspect arg}")
    args_into_pterms(t)
  end

  def maybe_create_essential do
    :ok = maybe_create_timestamp()
  end

  def maybe_create_timestamp do
    case read_env(:timestamp) do
      nil -> put_env(:timestamp, DateTime.to_unix(DateTime.utc_now()))
      _ -> :ok
    end
  end
  
  def put_env(arg, value) do
    :persistent_term.put({:deploy, :env, arg}, value)
  end

  def read_env(arg, default \\ nil) do
    :persistent_term.get({:deploy, :env, arg}, default)
  end

  def enforce_args({or_lists}) do
    Enum.reduce_while(or_lists, {:error, []}, fn(list_n, {:error, errors_acc}) ->
      case enforce_args(list_n) do
        :ok -> {:halt, :ok}
        {:missing_args, missing} -> {:cont, {:error, [missing | errors_acc]}}
      end
    end)
    |> case do
         :ok -> :ok
         {:error, args_missing} -> {:missing_args, args_missing}
       end
  end

  def enforce_args([_|_] = args) do
    Enum.reduce(args, [], fn(arg, acc) ->
      case read_env(arg) do
        nil -> [arg | acc]
        value ->
          case String.trim(value) do
            <<>> -> [arg | acc]
            _ -> [:ok | acc]
          end
      end
    end)
    |> Enum.reject(fn(v) -> v == :ok end)
    |> case do
         [] -> :ok
         missing -> {:missing_args, Enum.map(missing, fn(arg) -> missing_arg(arg) end)}
       end
  end

  def enforce_args([]), do: :ok

  def missing_arg(arg) do
    "Deployer Error ::::: -> Task requires argument #{arg} to be passed, eg: #{arg}=some_value"
  end

  def apply_mfa_bin(mfa_bin) do
    [mod, fun, args] =
      case String.split(mfa_bin, "#") do
        [module, function] -> [module, function, []]
        [module, function | args] -> [module, function, args]
        _ ->
          Logger.warn("Invalid formatting for Module/Function MFA: #{inspect mfa_bin} - expected something like \"Module#function#arg1#arg2\"")
          :ok
      end

    atom_module = String.to_atom("Elixir.#{mod}")
    function = String.to_atom(fun)
    apply(atom_module, function, args)
  end

  def make_deploy_conf(target) do
    target_conf = (
      read_env(:deployer_config, %{})
      |> Map.get(:targets, %{})
      |> Map.get(target)
    )

    case target_conf do
      nil -> {:missing_target_config_for, target}
      _ -> Deployer.Configuration.Context.validate_target(target_conf)
    end
  end

  def keyword_update_if_nil(klist, key, n_value) do
    Keyword.update(klist, key, n_value, fn(val) -> if(is_nil(val), do: n_value, else: val) end)
  end
  
end
