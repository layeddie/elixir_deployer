defmodule Deployer.Builder.Docker do
  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  defstruct [:before_run, :after_run, dockerfile: "Dockerfile", args: []]

  def build(
    %Deployer.Env{
      paths: %Deployer.Env.Paths{
        root_path: root_path,
        temp_path: temp_folder,
        release_path: final_release_folder
      },
      env: env,
      datetime: datetime,
      unix_ts: timestamp
    } = ctx,
    %Deployer.Configuration.Target{
      name: name,
      tags: tags
    } = target,
    docker_map
  ) do

    timestamped_name = "#{name}-#{timestamp}"
    temp_release_folder = Path.join(temp_folder, timestamped_name)

    env_file = Map.get(env, :env_file_name)

    try do
      
      with(
        {_, :ok} <- {:create_temp, File.mkdir_p(temp_release_folder)},
        {_, hooks} <- {:extract_pre_hooks, extract_hooks(:pre_hooks, docker_map)},
        {_, {:ok, n_ctx, n_target}} <- {:pre_build_hooks, run_pre_build_hooks(hooks, ctx, target)},
        {_, dockerfile} <- {:dockerfile, docker_env(docker_map, :dockerfile, "Dockerfile")},
        {_, docker_args} <- {:docker_args, docker_args(docker_map)},
        {_, :ok} <- {:docker_build, docker_build(name, timestamp, dockerfile, docker_args)},
        {_, :ok} <- {:docker_create, docker_create(name)},
        {_, :ok} <- {:docker_cp, docker_cp(name, temp_release_folder)},
        {_, :ok} <- {:cd_to_release, File.cd(temp_release_folder)},
        {_, :ok} <- {:tar_release, tar_release(name, timestamped_name, temp_release_folder)},
        {_, :ok} <- {:tar_add_env, maybe_add_env(env_file, timestamped_name)},
        {_, :ok} <- {:gzip_tar, gzip(timestamped_name)},
        {_, gziped_file} <- {:gziped_name, "#{timestamped_name}.tar.gz"},
        {_, gziped_temp_path} <- {:gziped_temp_path, Path.join(temp_release_folder, gziped_file)},
        {_, gziped_final_path} <- {:gziped_path, Path.join(final_release_folder, gziped_file)},
        {_, :ok} <- {:cd_to_root, File.cd(root_path)},
        {_, {:ok, _}} <- {:copy_release_tar, File.cp_r(gziped_temp_path, gziped_final_path)},
        {_, {:ok, data}} <- {:read_file, File.read(gziped_final_path)},
        {_, <<md5::binary>>} <- {:file_md5, :erlang.md5(data)}
      )  do
        
        AH.success("Successfully built and tar'ed #{name}.")
        
        rel = Deployer.Release.Context.create(
          %{
            path: gziped_final_path,
            name: name,
            created_at: datetime,
            tags: tags,
            unix_ts: timestamp,
            ref: Base.encode16(md5)
          }
        )

        {ctx, rel}
      else
        error ->
          AH.error("Docker.Builder error:\n #{inspect(error)}")
        {:error, error}
      end
      
    after
      case File.rm_rf(temp_release_folder) do
        {:ok, _} -> AH.success("Removed temp folders associated with the build")
        {:error, reason, file} -> AH.warn("Unable to remove temp folders associated with the build, #{inspect file}, with reason #{inspect reason}")
      end
      remove_stale(timestamped_name)
      cmd("docker rm #{name}")
    end
  end
  
  def remove_stale(timestamped_name) do
    cmd("docker container prune -f --filter \"label=#{timestamped_name}\"")
    cmd("docker image prune -f --filter \"label=#{timestamped_name}\"")
  end

  def docker_build(name, timestamp, dockerfile, docker_args),
    do: cmd("docker build \
    #{docker_args} \
    --rm=true -t #{name} \
    --build-arg deployer_ts=#{timestamp} \
    --build-arg deployer_name=#{name} \
    -f #{dockerfile} .")

  def docker_create(name),
    do: cmd("docker create --name #{name} #{name}")
  
  def docker_cp(name, temp_release_folder),
    do: cmd("docker cp #{name}:app/_build/prod - | tar -x -C #{temp_release_folder}")

  def tar_release(_name, timestamped_name, temp_release_folder),
    do: cmd("tar -cvf #{timestamped_name}.tar -C #{temp_release_folder}/prod/rel/ .")

  def maybe_add_env(env_file, timestamped_name) when env_file,
    do: cmd("tar -r --file=#{timestamped_name}.tar #{env_file}")
  
  def maybe_add_env(_, _),
    do: :ok

  def gzip(timestamped_name),
    do: cmd("gzip #{timestamped_name}.tar")
  
  defp cmd(command, options \\ [], fun \\ &Mix.Shell.IO.info/1) when is_binary(command) do
    case Mix.Shell.cmd(command, options, fun) do
      0 -> :ok
      other -> other
    end
  end

  defp docker_args(%{args: args}) do
    Enum.map_join(args, " ", fn({k, v}) -> "#{k}=#{v}" end)
  end

  defp docker_args(_), do: ""

  defp docker_env(%{} = docker_map, key, default) do
    Map.get(docker_map, key, default) 
  end

  defp extract_hooks(hooks_type, %{} = docker_map) do
    case Map.get(docker_map, hooks_type) do
      nil -> []
      [_|_] = hooks -> hooks
      {_, _, _} = hook -> [hook]
    end
  end

  defp extract_hooks(_, _), do: []

  defp run_pre_build_hooks([], ctx, target), do: {:ok, ctx, target}

  defp run_pre_build_hooks([{m, f, a} | t], ctx, target) do
    case apply(m, f, [ctx, target, [a]]) do
      :ok -> run_pre_build_hooks(t, ctx, target)
      {:ok, n_ctx, n_target} -> run_pre_build_hooks(t, n_ctx, n_target)
      error -> error
    end
  end

  defp run_pre_build_hooks([_ | t], ctx, target), do: run_pre_build_hooks(t, ctx, target)
  
end
