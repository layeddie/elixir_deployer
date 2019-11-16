defmodule Mix.Tasks.Deployer.Stop do
  use Mix.Task

  alias Deployer.Env, as: Env

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  alias Deployer.SSH
  
  @required_args [:target]

  def run(args \\ []) do
    with(
      {_, %Env{} = ctx} <- {:load_ctx, DH.load_config(args)},
      {_, :ok} <- {:enforce_args, DH.enforce_args(ctx, @required_args)},
      {_, {:ok, conf}} <- {:make_deploy_conf, DH.make_deploy_conf(ctx)},
      {_, {:ok, name}} <- {:try_ssh_connect, Mix.Tasks.Deployer.Ssh.run(ctx)},
      {_, path} when is_binary(path) <- {:conf_target_path, Map.get(conf, :path, :no_deployer_path_for_target)},
      {_, :ok} <- {:check_if_has_existing_remote, AH.warn("Checking if deployer has been init in the remote server")},
      {_, {0, _}} <- {{:has_deployer_remote, path}, SSH.execute("test -e #{path}/config/deployer_info", name)},
      {_, :ok} <- {:send_stop, send_stop(conf, name)}
    ) do
      AH.success("Stopped!")
    else
      {:has_deployer_remote, _} ->
        AH.error("It seems the remote host deployer hasn't been initiated yet.")
      error ->
        AH.error("Error: #{inspect error}")
    end
  end

  def send_stop(%{path: path, name: app_name}, name) do
    full_path = "#{path}/releases/current/#{app_name}/bin/#{app_name} stop"
    case SSH.execute(full_path, name) do
      {0, _} -> :ok
      error -> error
    end
  end
end
