defmodule Mix.Tasks.Deployer.Deploy do
  use Mix.Task
  
  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH
  require AH

  alias Deployer.SSH

  @base_remote_config %{
    releases: [],
    current_deploying: false,
    current_symlink: false
  }

  @required_args [:target]

  @shortdoc "Deploys a Release Tar to a Host Server"
  def run(args \\ []) do

    
    
    with(
      {_, :ok} <- {:set_deployer_paths, DH.Paths.set_deployer_paths()},
      {_, true} <- {:deployer_init?, DH.Paths.is_initialised?()},
      {_, :ok} <- {:parsing_args, DH.args_into_pterms(args)},
      {_, :ok} <- {:enforce_args, DH.enforce_args(@required_args)},
      {_, :ok} <- {:check_release, check_release(DH.read_env(:release))},
      {_, :ok} <- {:add_names, DH.maybe_create_essential()},
      {_, {:ok, conf}} <- {:make_deploy_conf, DH.make_deploy_conf()},
      {_, {:ok, name}} <- {:try_ssh_connect, Mix.Tasks.Deployer.Ssh.run([])},
      {_, {:ok, remote_info}} <- {:maybe_create_remote_structure, maybe_create_remote_structure(conf, name)},
      {_, {:ok, n_remote_info}} <- {:check_stale_deployments, check_stale(remote_info, conf, name)}
    ) do
      AH.success("Finished Deploying: #{inspect n_remote_info}")
    else
      error ->
        AH.error("Deployer Error: #{inspect error}")
    end
  end

  def maybe_create_remote_structure(conf, name) do
    with(
      {_, path} when is_binary(path) <- {:conf_target_path, Keyword.get(conf, :path, :no_deployer_path_for_target)},
      {_, :ok} <- {:check_if_has_existing_remote, AH.warn("Checking if deployer has been init in the remote server")},
      {_, {1, _}} <- {{:has_deployer_remote, path}, SSH.execute("test -e #{path}", name)},
      {_, :ok} <- {:creating_deployer_base, AH.warn("Deployer hasn't been init. Creating deployer base structure on remote server")},
      {_, {0, _}} <- {:mkdir_deployer_base, SSH.execute("mkdir -p #{path}/{config,releases/{current/deployed}}", name)},
      {_, :ok} <- {:creating_info_file, AH.warn("Successfully created structure, storing base config")},
      {_, {0, _}} <- {:create_info_file, SSH.execute("printf %s '#{inspect(@base_remote_config)}' > #{path}/config/deployer_info", name)},
      {_, :ok} <- {:created_remote_config, AH.success("Successfully stored base config")}
    ) do
      {:ok, @base_remote_config}
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
  
  defp check_stale(%{current_deploying: ref} = remote_info, conf, name) when ref do
    case AH.wait_input("A deployment hasn't completed >> deploy ref: #{ref} - Do you want to remove it and proceed? [Yna] (answer Y for yes, n for no or a to abort)") do
      "Y\n" -> remove_stale(remote_info, conf, name)
      "n\n" -> change_stale(remote_info, conf, name)
      "a\n" -> {:error, {:stale_deployment, :aborted}}
      input ->
        AH.error("Invalid option: " <> String.trim_trailing(input))
        check_stale(remote_info, conf, name)
    end
  end

  defp check_stale(remote_info, _conf, _name) do
    {:ok, %{remote_info | current_deploying: DH.read_env(:release)}}
  end

  defp remove_stale(%{current_deploying: ref} = remote_info, conf, name) do
    with(
      {_, path} when is_binary(path) <- {:conf_target_path, Keyword.get(conf, :path, :no_deployer_path_for_target)},
      {_, :ok} <- {:attempting_to_remove_stale, AH.warn("Attempting to remove #{ref}")},
      {_, {0, _}} <- {:remove_stale, SSH.execute("rm -rf #{path}/releases/#{ref}", name)}
    ) do
      AH.success("Removed Stale deployment")
      new_ref = DH.read_env(:release)
      {:ok, %{remote_info | current_deploying: new_ref}}
    else
      error -> error
    end
  end

  defp change_stale(remote_info, _conf, _name) do
    new_ref = DH.read_env(:release)
    {:ok, %{remote_info | current_deploying: new_ref}}
  end

  def check_release(release) do
    case DH.DETS.get_existing_releases() do
      {:ok, [_|_] = releases} ->
        case {release, DH.DETS.check_release_exists(release, releases)} do
          {r, true} when not is_nil(r) -> :ok
          _ -> re_pick_release(release, releases)
        end
      {:ok, []} -> {:error, :no_available_releases}
      error -> error
    end
  end

  def re_pick_release(release, releases) do
    if release do
      AH.warn("Release with ref: #{release} wasn't found.")
    else
      AH.warn("You haven't specified a release ref.")
    end
    AH.warn("Please enter the ID of the release (enter \a to abort):")
    format_releases(releases)
    |> AH.response()
    
    case AH.wait_input("") |> String.trim_trailing() do
      "\\a" -> {:error, :no_existing_release}
      pick ->
        case DH.DETS.check_release_exists(pick, releases) do
          true -> DH.put_env(:release, pick)
          _ -> re_pick_release(pick, releases)
        end
    end
  end

  def format_releases(releases) do
    ["Id, Name,Timestamp" |
     Enum.map(releases, fn(%{name: name, id: id, created_at: dt}) ->
       "#{id}, #{name}, #{DateTime.to_iso8601(dt)}"
     end)
    ]
  end
end
