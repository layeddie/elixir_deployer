defmodule Deployer.Docker.Builder do
  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH
  require AH

  def build do
    %{name: name} = DH.read_env(:deployer_config)
    timestamp = DH.read_env(:timestamp)
    timestamped_name = "#{name}-#{timestamp}"

    root_path = DH.read_env(:deployer_root_path)
    temp_release_folder = DH.read_env(:deployer_temp_path)
    final_release_folder = DH.read_env(:deployer_release_path)
    
    dockerfile = (DH.read_env(:dockerfile) || "Dockerfile")
    docker_rebuild = (DH.read_env(:docker_rebuild) && "--no-cache" || "")
    env_file = DH.read_env(:env_file_name)

    try do
      
      with(
        {_, :ok} <- {:docker_build, docker_build(name, timestamp, dockerfile, docker_rebuild)},
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
        {_, {:ok, _}} <- {:copy_release_tar, File.cp_r(gziped_temp_path, gziped_final_path)}
      )  do
        
        AH.success("Successfully built and tar'ed #{name}.")
        
        Deployer.Release.Context.create(
          %{
            path: gziped_final_path,
            name: name,
            created_at: DateTime.from_unix(timestamp) |> elem(1)
          }
        )
      else
        error ->
          AH.error("Docker.Builder error:\n #{inspect(error)}")
        {:error, error}
      end
      
    after
      remove_stale(timestamped_name)
      cmd("docker rm #{name}")
    end
  end
  
  def remove_stale(timestamped_name) do
    cmd("docker container prune -f --filter \"label=#{timestamped_name}\"")
    cmd("docker image prune -f --filter \"label=#{timestamped_name}\"")
  end

  def docker_build(name, timestamp, dockerfile, docker_rebuild),
    do: cmd("docker build #{docker_rebuild} \
    --rm=true -t #{name} \
    --build-arg deployer_ts=#{timestamp} \
    --build-arg deployer_name=#{name} \
    -f #{dockerfile} .")

  def docker_create(name),
    do: cmd("docker create --name #{name} #{name}")
  
  def docker_cp(name, temp_release_folder),
    do: cmd("docker cp #{name}:app/_build/prod - | tar -x -C #{temp_release_folder}")

  def tar_release(name, timestamped_name, temp_release_folder),
    do: cmd("tar -cvf #{timestamped_name}.tar -C #{temp_release_folder}/prod/rel/#{name}/ .")

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
end
