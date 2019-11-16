defmodule Deployer.Helpers.Remote do

  @base_remote_config %{
    releases: [],
    current_deploying: false,
    current_symlink: false
  }

  alias Deployer.Release, as: Rel

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH
  
  alias Deployer.SSH
  alias SSH.Sendfile
  
  def maybe_create_remote(conf, name) do
    with(
      {_, path} when is_binary(path) <- {:conf_target_path, Map.get(conf, :path, :no_deployer_path_for_target)},
      {_, :ok} <- {:check_if_has_existing_remote, AH.warn("Checking if deployer has been init in the remote server")},
      {_, {1, _}} <- {{:has_deployer_remote, path}, SSH.execute("test -e #{path}/config/deployer_info", name)},
      {_, :ok} <- {:creating_deployer_base, AH.warn("Deployer hasn't been init. Creating deployer base structure on remote server")},
      {_, {0, _}} <- {:mkdir_deployer_base, SSH.execute("mkdir -p #{path}/{config,releases}", name)},
      {_, :ok} <- {:creating_info_file, AH.warn("Successfully created structure, storing base config")},
      {_, {:ok, rem_config}} <- {:create_info_file, write_remote_config(@base_remote_config, path, name)},
      {_, :ok} <- {:created_remote_config, AH.success("Successfully stored base config")}
    ) do
      {:ok, rem_config}
    else
      {{:has_deployer_remote, path}, {0, _}} ->
        AH.warn("Deployer has already been init in the remote server, checking remote config...")
      read_remote_config(path, name)
      error ->
        {:error, error}
    end
  end

  defp read_remote_config(path, name) do
    case SSH.execute("cat #{path}/config/deployer_info", name) do
      {0, contents} ->
        case Code.eval_string(contents) do
          {config, _} ->
            AH.success("Valid config found.")
            {:ok, config}
          _ -> {:error, :reading_config, contents}
        end
      {posix_code, _} -> {:has_deployer_remote, :unable_to_read_remote_config, {:return_code, posix_code}}
    end
      end

  def write_remote_config(config, path, name) do
    case SSH.execute("printf %s '#{inspect(config)}' > #{path}/config/deployer_info", name) do
      {0, _} ->
        AH.info("Wrote new config to remote.")
        {:ok, config}
      error ->
        AH.info("Error writing config to remote... #{inspect error}")
        error
    end
  end

  def symlink(%Sendfile{dest: dest}, remote_info, %Rel{} = rel, name) do
    dest_folder = String.split(dest, "/") |> Enum.reverse() |> hd()
    command = "cd #{dest} && cd .. && echo $(pwd) && ln -nsf #{dest_folder} current"
    case SSH.execute(command, name) do
      {0, _} -> {:ok, %{remote_info | current_symlink: rel, current_deploying: false}}
      error -> {:error, :remote_posix, error}
    end
  end

  # TODO fix the way the path is computed for the symlink
  def symlink(rel_path, remote_info, %Rel{} = rel, name) do
    case SSH.execute("cd #{rel_path} && cd .. && ln -nsf ~/#{rel_path} current", name) do
      {0, _} -> {:ok, %{remote_info | current_symlink: rel}}
      error -> {:error, :remote_posix, error}
    end
  end

  def build_paths(store_path, ref, rel_name) do
    rel_path = "#{store_path}/releases/deployer_#{ref}"
    %{
      rel_path: rel_path,
      rel_base: "#{rel_path}/#{rel_name}"
    }
  end
end
