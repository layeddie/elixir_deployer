defmodule Deployer.Env.Paths do
  use Ecto.Schema

  @type env_options :: [
    base_path: String.t,
    config_folder: String.t,
    config_file: String.t,
    release_folder: String.t,
    temp_folder: String
  ]

  @base_path "deployer"
  @config_folder "config"
  @config_file "deployer_config.ex"
  @release_folder "release_store"
  @temp_folder "temp"

  alias Deployer.Helpers

  @derive Jason.Encoder
  @primary_key false

  embedded_schema do
    field :root_path,          :string
    field :base_path,          :string
    field :config_path,        :string
    field :config_file,        :string
    field :release_path,       :string
    field :temp_path,          :string
    field :dets_path,          :string
    field :dets_path_charlist, {:array, :integer}
  end


  def priv_config_file_path do
    Path.join([:code.priv_dir(:deployer), "templates", @config_file])
  end

  @spec create(env_options) :: %__MODULE__{}
  def create(opts \\ []) do

    deployer_folder = Keyword.get(opts, :base_path, @base_path)
    config_folder = Keyword.get(opts, :config_folder, @config_folder)
    deployer_config_file = Keyword.get(opts, :config_file, @config_file)
    release_folder = Keyword.get(opts, :release_folder, @release_folder)
    temp_folder = Keyword.get(opts, :temp_folder, @temp_folder)
    
    with(
      {_, root_path} when is_binary(root_path) <- {:root_path, get_root_path()},
      {_, true} <- {:root_path_exists, File.exists?(root_path)},
      {_, base_path} <- {:base_path, Path.join(root_path, deployer_folder)},
      {_, config_path} <- {:config_path, Path.join(base_path, config_folder)},
      {_, config_file} <- {:config_file_path, Path.join(config_path, deployer_config_file)},
      {_, release_path} <- {:release_store_path, Path.join(base_path, release_folder)},
      {_, temp_path} <- {:temp_path, Path.join(base_path, temp_folder)},
      {_, dets_path} <- {:dets_path, build_dets_path(config_path)},
      {_, dets_path_charlist} <- {:dets_path_charlist, String.to_charlist(dets_path)}
    ) do
      
      %__MODULE__{
        root_path: root_path,
        base_path: base_path,
        config_path: config_path,
        config_file: config_file,
        release_path: release_path,
        temp_path: temp_path,
        dets_path: dets_path,
        dets_path_charlist: dets_path_charlist
      }
      
    else
      error ->
        {:error, :setting_base_path, error}
    end
  end

  defp get_root_path do
    if Mix.Project.umbrella?() do 
      split_paths = Application.app_dir(:deployer) |> String.split("/_build/")
      case split_paths  do
        [path, _] -> path
        paths -> {:more_paths_than_expected, paths}
      end
    else
      Mix.Project.app_path()
    end
  end

  defp build_dets_path(config_path) do
    config_path
    |> Deployer.Helpers.DETS.path()
  end

end
