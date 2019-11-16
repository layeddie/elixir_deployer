defmodule Mix.Tasks.Deployer.Init do
  use Mix.Task
  require Logger

  alias Deployer.Env
  
  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  @shortdoc "Creates the initial folder to store the release artifacts and sets up the versioning and othe infrastructure details"

  def run(args) do
    with(
      {_, project} when not(is_nil(project)) <- {:get_project, Mix.Project.get()},
      {_, %Env{} = ctx} <- {:load_paths, DH.load_config(:bootstrap, args)},
      {_, :ok} <- {:create_deployer_structure, create_deployer_structure(ctx)}
    ) do
      AH.success("Initialized Succesfully the Deployer")
      :ok
    else
      error ->
        AH.error(error)
      error
    end
  end
  
  defp create_deployer_structure(
    %Env{
      paths: %Env.Paths{
        base_path: base_path,
        config_path: config_path,
        config_file: config_file,
        release_path: release_path
        }
    } = ctx
  ) do
    with(
      {_, :ok} <- {:create_deployer_dir, File.mkdir(base_path)},
      {_, :ok} <- {:create_config_dir, File.mkdir(config_path)},
      {_, :ok} <- {:create_config_file, create_config_file(config_file)},
      {_, :ok} <- {:create_release_store_path, File.mkdir(release_path)},
      {_, :ok} <- {:populate_dets, DH.DETS.create_dets_entries(ctx)}
    ) do
      :ok
    else
      {:create_deployer_dir, {:error, :eexist}} ->
        case DH.read_env(ctx, :force_init) do
          nil ->
            {:error, "The Deployer folder (#{base_path}) has already been created, if you wish to re-init it from scratch, pass the flag -force_init, this will delete any previous releases and configurations you might have."}
          true ->
            File.rm_rf!(base_path)
            create_deployer_structure(ctx)
        end
      error ->
        File.rm_rf!(base_path)
        error
    end
  end

  defp create_config_file(config_file_path) do
    config_template_path = Deployer.Env.Paths.priv_config_file_path()
    File.cp(config_template_path, config_file_path)
  end
end
