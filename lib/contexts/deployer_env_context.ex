defmodule Deployer.ENV.Context do
  
  alias Deployer.ENV
  alias ENV.Paths, as: ENVP

  alias Deployer.Configuration, as: Config
  alias Config.Context, as: CTX

  
  def create do
    with(
      {_, %ENVP{config_file: file, config_path: path} = envp} <- {:create_paths, ENVP.create()},
      {_, true} <- {:is_deployer_init?, File.exists?(config_file)},
      {_, {config, _}} <- {:eval_config, Code.eval_file("deployer_config.ex", config_path)},
      {:ok, %Config{} = n_config} <- {:create_config, CTX.create_configuration(config)},
      datetime <- DateTime.utc_now(),
      timestamp <- DateTime.to_unix(datetime)
    ) do

      {
        :ok,
        %__MODULE__{paths: envp, config: n_config, datetime: datetime, unix_ts: timestamp}
      }

    else
      error -> {:error, :creating_config, error}
    end
  end
end
