defmodule Mix.Tasks.Deployer.Init do
  use Mix.Task
  require Logger

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH
  require AH

  @shortdoc "Creates the initial folder to store the release artifacts and sets up the versioning and other infrastructure details"

  def run(args) do
    with(
      {_, :ok} <- {:parsing_args, DH.args_into_pterms(args)},
      {_, project} when not(is_nil(project)) <- {:get_project, Mix.Project.get()},
      {_, :ok} <- {:set_base_paths, DH.Paths.set_deployer_paths()},
      {_, :ok} <- {:create_deployer_structure, create_deployer_structure()},
      {_, :ok} <- {:close_dets, DH.DETS.close()}
    ) do
      AH.success("Initialized Succesfully the Deployer")
      :ok
    else
      error ->
        AH.error(error)
      error
    end
  end
    
  defp create_deployer_structure do
    deployer_path = DH.read_env(:deployer_path)
    config_path = DH.read_env(:deployer_config_path)
    release_path = DH.read_env(:deployer_release_path)
    with(
      {_, :ok} <- {:create_deployer_dir, File.mkdir(deployer_path)},
      {_, :ok} <- {:create_config_dir, File.mkdir(config_path)},
      {_, :ok} <- {:create_config_file, create_config_file(config_path)},
      {_, :ok} <- {:create_release_store_path, File.mkdir(release_path)},
      {_, :ok} <- {:populate_dets, DH.DETS.create_dets_entries()}
    ) do
      :ok
    else
      {:create_deployer_dir, {:error, :eexist}} ->
        case DH.read_env(:force_init) do
          nil ->
            {:error, "The Deployer folder (#{deployer_path}) has already been created, if you wish to re-init it from scratch, pass the flag -force_init, this will delete any previous releases and configurations you might have."}
          true ->
            File.rm_rf!(deployer_path)
            create_deployer_structure()
        end
      error ->
        File.rm_rf!(deployer_path)
        error
    end
  end

  defp create_config_file(config_path) do
    config_file = "deployer_config.ex"
    config_template_path = Path.join([:code.priv_dir(:deployer), "templates", config_file])
    config_file_path = Path.join(config_path, config_file)
    File.cp(config_template_path, config_file_path)
  end
end
