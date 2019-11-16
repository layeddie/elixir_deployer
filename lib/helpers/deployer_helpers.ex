defmodule Deployer.Helpers do
  require Logger

  alias Deployer.Env, as: Env

  @spec load_config(:bootstrap | %Env{}) :: %Env{} | any()
  def load_config(:bootstrap, args) do
    with(
      {_, %Env{} = ctx} <- {:create_ctx, Env.Context.create(:bootstrap)},
      {_, %Env{} = n_ctx} <- {:parse_args, env_from_args(args, ctx)}
    ) do
      n_ctx
    else
      error -> error
    end
  end

  def load_config(%Env{} = ctx, args) when is_list(args) do
    env_from_args(ctx, args)
  end
  
  def load_config(%Env{} = ctx), do: ctx
  
  def load_config(args) when is_list(args) do
    with(
      {_, %Env{} = ctx} <- {:create_ctx, Env.Context.create()},
      {_, %Env{} = n_ctx} <- {:parse_args, env_from_args(args, ctx)}
    ) do
      n_ctx
    else
      error -> error
    end
  end

  def env_from_args(entries, acc)
  def env_from_args([], %Env{} = acc), do: acc

  def env_from_args([entry | t], %Env{env: acc} = env) when is_binary(entry) do
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
    env_from_args(t, %Env{env | env: n_acc})
  end

  def env_from_args([{arg, value} | t], %Env{env: acc} = env) when is_atom(arg) do
    n_acc = Map.put(acc, arg, value)
    env_from_args(t, %Env{env | env: n_acc})
  end

  def env_from_args([{arg, value} | t], %Env{env: acc} = env) when is_binary(arg) do
    n_acc = Map.put(acc, String.to_atom(arg), value)
    env_from_args(t, %Env{env | env: n_acc})
  end

  def env_from_args([arg | t], %Env{} = env) do
    Logger.warn("Invalid argument passed #{inspect arg}")
    env_from_args(t, env)
  end

  def put_env(%Env{env: env} = full, arg, val) do
    %{full | env: Map.put(env, arg, val)}
  end

  def read_env(%Env{env: env}, arg, default \\ nil) do
    Map.get(env, arg, default)
  end

  def remove_env(%Env{env: env} = full, arg) do
    {_, n_env} = Map.pop(env, arg)
    %{full | env: n_env}
  end

  def decide_builder(%Env{env: env} = ctx) do
    target = Map.get(env, :target, nil)
    check_if_has_target(target, ctx)
  end

  def check_if_has_target(target, %Env{config: config} = ctx) when is_map(config) do
    Map.get(config, :targets, %{})
    |> Map.get(target, nil)
    |> case do
         nil -> {:no_target_found, target}
         %{builder: builder} = target_ctx ->
           builder_to_check = builder || target
           case check_if_has_builder_env(builder_to_check, ctx) do
             {:ok, {m, f, a}} -> {:ok, {m, f, [target_ctx | a]}}
             _ -> {:ok, {Deployer.Builder.Default, :build, [target_ctx]}}
           end
       end
  end

  def check_if_has_target(_, _), do: :invalid_config

  def check_if_has_builder_env(builder, %Env{config: config}) when is_map(config) do
    Map.get(config, :builders, %{})
    |> Map.get(builder, nil)
    |> case do
         nil ->
           case parse_mfa_bin(builder) do
             {:ok, {m, f, a}} -> {:ok, {m, f, a}}
             _ -> :no_builder_found
           end
         builder_def -> {:ok, builder_def}
       end
  end
  
  def check_if_has_builder_env(_, _), do: :invalid_config

  def enforce_args(%Env{} = ctx, {or_lists}) do
    Enum.reduce_while(or_lists, {:error, []}, fn(list_n, {:error, errors_acc}) ->
      case enforce_args(ctx, list_n) do
        :ok -> {:halt, :ok}
        {:missing_args, missing} -> {:cont, {:error, [missing | errors_acc]}}
      end
    end)
    |> case do
         :ok -> :ok
         {:error, args_missing} -> {:missing_args, args_missing}
       end
  end

  def enforce_args(%Env{} = ctx, [_|_] = args) do
    Enum.reduce(args, [], fn(arg, acc) ->
      case read_env(ctx, arg) do
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
         missing -> {:missing_args, missing}
       end
  end

  def enforce_args(_, []), do: :ok


  def apply_mfa_bin(mfa_bin) when is_binary(mfa_bin) do
    case parse_mfa_bin(mfa_bin) do
      {mod, fun, args} -> apply(mod, fun, args)
      error ->
        Logger.warn("Invalid formatting for Module/Function MFA: #{inspect mfa_bin} - expected something like \"Module#function#arg1#arg2\"")
        error
    end
  end

  def apply_mfa_bin(mfa_bin), do: {:error, :applying_mfa_bin, :must_be_binary, mfa_bin}

  def parse_mfa_bin(mfa_bin) when is_binary(mfa_bin) do
    case split_mfa_bin(mfa_bin) do
      {:ok, [mod, fun, args]} ->        
        atom_module = String.to_atom("Elixir.#{mod}")
        function = String.to_atom(fun)
        {:ok, {atom_module, function, args}}

      error -> error
    end
  end

  def parse_mfa_bin(mfa_bin), do: {:error, :parsing_mfa_bin, :must_be_binary, mfa_bin}

  def split_mfa_bin(mfa_bin) when is_binary(mfa_bin) do
    case String.split(mfa_bin, "#") do
      [module, function] -> {:ok, [module, function, []]}
      [module, function | args] -> {:ok, [module, function, args]}
      _ -> {:error_mfa_bin, mfa_bin}
    end
  end

  def split_mfa_bin(mfa_bin), do: {:error, :splitting_mfa_bin, :must_be_binary, mfa_bin}

  def make_deploy_conf(%Env{config: config} = ctx) when is_map(config) do
    target = read_env(ctx, :target)
    
    target_conf = (
      Map.get(config, :targets, %{})
      |> Map.get(target, nil)
    )

    case target_conf do
      nil -> {:missing_target_config_for, target}
      _ -> Deployer.Configuration.Context.validate_target(target_conf)
    end
  end

  def keyword_update_if_nil(klist, key, n_value) do
    Keyword.update(klist, key, n_value, fn(val) -> if(is_nil(val), do: n_value, else: val) end)
  end

  def decide_release(%Env{config: config} = ctx) when is_map(config) do
    case read_env(ctx, :release) do
      nil ->
        case read_env(ctx, :target) do
          nil -> nil
          target ->
            Map.get(config, :targets, %{})
            |> Map.get(target, nil)
            |> case do
                 nil -> nil
                 %{name: name} -> name
               end
        end
      name_or_id -> name_or_id
    end
  end

  def extract_valid_targets(%Env{config: config} = ctx) when is_map(config) do
    targets = Map.get(config, :targets, %{})
    
    Enum.reduce(targets, [], fn({k, v}, acc) ->
      %{host: host, user: user, name: name, path: path} = v
      case host && user && name && path do
        a when a in [nil, false] -> acc
        _ -> [{k, host, user, name} | acc]
      end
    end)
  end
end
