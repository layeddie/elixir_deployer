defmodule Mix.Tasks.Deployer.Deploy do
  use Mix.Task

  alias Deployer.Release, as: Rel
  alias Deployer.Env
  
  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  alias Deployer.SSH
  alias SSH.Sendfile

  @required_args [:target]

  @shortdoc "Deploys a Release Tar to a Host Server"
  def run(args \\ []) do
    try do
      with(
        {_, %Env{} = ctx} <- {:load_ctx, DH.load_config(args)},
        {_, :ok} <- {:enforce_args, DH.enforce_args(ctx, @required_args)},
        {_, %Rel{ref: rel_ref} = rel} <- {:check_release, check_release(ctx)},
        {_, {:ok, conf}} <- {:make_deploy_conf, DH.make_deploy_conf(ctx)},
        {_, {:ok, name}} <- {:try_ssh_connect, Mix.Tasks.Deployer.Ssh.run(ctx)},
        {_, {:ok, remote_info}} <- {:create_remote?, DH.Remote.maybe_create_remote(conf, name)},
        {_, {:ok, n_rem_info_2}} <- {:stale_deployments?, check_stale(remote_info, conf, name)},
        %{releases: releases} <- n_rem_info_2,
        [_|_] = new_releases <- make_uniq_rels([rel | Rel.remove_latest(releases, rel.name)]),
        n_rem_info_3  <- %{n_rem_info_2 | current_deploying: "#{rel_ref}", releases: new_releases},
        {_, {:ok, %Sendfile{} = upload}} <- {:uploading_release, SSH.upload_release(name, rel, conf)},
        {_, :ok} <- {:untar_release, untar_release(upload, name)},
        {_, {:ok, n_rem_info_4}} <- {:symlink, DH.Remote.symlink(upload, n_rem_info_3, rel, name)},
        {_, :ok} <- {:writing_info_after_deployment, write_info(n_rem_info_4, conf, name)}
      ) do
        AH.success("Finished Deploying! #{rel.name}")
        IO.inspect(n_rem_info_4, label: "Current Versions Stored in the Remote Host")
        {:ok, ctx}
      else
        error ->
          AH.error("Deployer Error: #{inspect error}")
      end
    after
      DH.DETS.close()
    end
  end

  defp check_stale(%{current_deploying: ref} = remote_info, conf, name) when ref do
    case AH.wait_input("A deployment hasn't completed >> deploy ref: #{ref} - Do you want to remove it and proceed? [Yna] (answer Y for yes, n to keep the release in the remote or a to abort)") do
      "Y" -> remove_stale(remote_info, conf, name)
      "n" -> {:ok, remote_info}
      "a" -> {:error, {:stale_deployment, :aborted}}
      input ->
        AH.error("Invalid option: " <> String.trim_trailing(input))
        check_stale(remote_info, conf, name)
    end
  end

  defp check_stale(remote_info, _conf, _name), do: {:ok, remote_info}

  defp remove_stale(%{current_deploying: ref, releases: releases} = rem_info, conf, name) do
    with(
      {_, path} when is_binary(path) <- {:conf_target_path, Map.get(conf, :path, :no_deployer_path_for_target)},
      {_, :ok} <- {:attempting_to_remove_stale, AH.warn("Attempting to remove #{ref}")},
      {_, {0, _}} <- {:remove_stale, SSH.execute("rm -rf #{path}/releases/deployer_#{ref}", name)}
    ) do
      AH.success("Removed Stale deployment")
      {:ok, %{rem_info | releases: Enum.reject(releases, fn(%{ref: r_ref}) -> r_ref == ref end)}}
    else
      error -> error
    end
  end

  defp write_info(remote_info, conf, name) do
    with(
      {_, path} when is_binary(path) <- {:conf_target_path, Map.get(conf, :path, :no_deployer_path_for_target)},
      {_, {0, _}} <- {:create_info_file, SSH.execute("printf %s '#{inspect(remote_info)}' > #{path}/config/deployer_info", name)},
      {_, :ok} <- {:created_remote_config, AH.success("Updated remote stored base config.")}
    ) do
      :ok
    else
      error -> error
    end
  end

  def check_release(%Env{} = ctx) do
    release = DH.decide_release(ctx)
    
    case DH.DETS.get_existing_releases(ctx) do
      {:ok, [_|_] = releases} ->
        case {release, DH.DETS.get_if_release_exists(release, releases)} do
          {r, %Rel{} = rel} when not is_nil(r) -> rel
          {_, {:by_latest, %Rel{} = rel}} -> maybe_accept_latest(rel, releases)
          _ -> re_pick_release(release, releases)
        end
      {:ok, []} -> {:error, :no_available_releases}
      error -> error
    end
  end

  def re_pick_release(release, releases) do
    if release do
      AH.warn("Release with id/name: #{release} wasn't found.")
    else
      AH.warn("You haven't specified a release ref.")
    end
    AH.warn("Please enter the ID of the release (enter \a to abort):")
    format_releases(releases)
    |> AH.response()
    
    case AH.wait_input("") do
      "\\a" -> {:error, :no_existing_release}
      pick ->
        case DH.DETS.get_if_release_exists(pick, releases) do
          %Rel{} = rel -> rel
          {:by_latest, rel} -> maybe_accept_latest(rel, releases)
          _ -> re_pick_release(pick, releases)
        end
    end
  end

  def format_releases(releases) do
    ["Id - Name ::: Tags ::: Timestamp" |
     Enum.map(releases, fn(%{name: name, id: id, created_at: dt, tags: tags}) ->
       "#{id} - #{name} ::: #{Enum.join(tags, " - ")} ::: #{DateTime.to_iso8601(dt)}"
     end)
    ]
  end

  def maybe_accept_latest(%Rel{name: name} = rel, releases) do
    case AH.wait_input(IO.ANSI.green() <> "Release with name #{name} picked by `latest` tag. Deploy?" <> IO.ANSI.default_color() <> " [Yn]") do
      "Y" -> rel
      _ -> re_pick_release(nil, releases)
    end
  end

  def make_uniq_rels(releases) do
    Enum.uniq_by(releases, fn(%{ref: ref}) -> ref end)
  end

  def untar_release(%Sendfile{name: filename, dest: dest}, name) do
    case SSH.execute("cd #{dest} && tar -xzf #{filename} && rm #{filename}", name) do
      {0, _} -> :ok
      {code, any} -> {:error, :remote_posix, code, any}
    end 
  end
end
