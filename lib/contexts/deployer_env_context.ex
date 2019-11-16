defmodule Deployer.Env.Context do
  
  alias Deployer.Env
  alias Env.Paths, as: Envp

  alias Deployer.Configuration, as: Configuration
  alias Deployer.Configuration.Context, as: CTX

  def create(:bootstrap) do
    with(
      {_, %Envp{config_file: file} = envp} <- {:create_paths, Envp.create()},
      datetime <- DateTime.utc_now(),
      timestamp <- DateTime.to_unix(datetime)
    ) do
      %Env{paths: envp, datetime: datetime, unix_ts: timestamp}
    else
      error -> {:error, :loading_config, error}
    end
  end
  
  def create do
    with(
      {_, %Envp{config_file: file} = envp} <- {:create_paths, Envp.create()},
      {_, true} <- {:is_deployer_init?, File.exists?(file)},
      {_, config} <- {:read_config, read_config(file)},
      {_, {:ok, %Configuration{} = n_config}} <- {:create_config, CTX.create_config(config)},
      datetime <- DateTime.utc_now(),
      timestamp <- DateTime.to_unix(datetime)
    ) do

      %Env{paths: envp, config: n_config, datetime: datetime, unix_ts: timestamp}
    else
      error -> {:error, :loading_config, error}
    end
  end

  def read_config(file) do
    config = Config.Reader.read!(file)
    Enum.into(config, %{}, fn({k, v}) ->
      {
        k,
        Enum.into(v, %{}, fn({k2, v2}) ->
          {
            Atom.to_string(k2),
            case v2 do
              {_, _, _} -> v2
              _ ->
                Enum.into(v2, %{}, fn({k3, v3}) ->
                  {k3, v3}
                end)
            end
          }
        end)
      }
    end)
  end 
end
