defmodule Deployer.ENV.Paths do
  use Ecto.Schema

  alias Deployer.Helpers

  @derive Jason.Encoder
  @primary_key false

  embedded_schema do
    field :root_path,    :string
    field :base_path,    :string
    field :config_path,  :string
    field :config_file,  :string
    field :release_path, :string
    field :temp_path,    :string
    field :dets_path,    {:array, :integer}
  end

  @spec create() :: %__MODULE__{}
  def create do
    with(
      {_, root_path} when is_binary(root_path) <- {:root_path, Helpers.Paths.get_root_path()},
      {_, true} <- {:root_path_exists, File.exists?(root_path)},
      {_, base_path} <- {:base_path, Path.join(root_path, "deployer")},
      {_, config_path} <- {:config_path, Path.join(base_path, "config")},
      {_, config_file} <- {:config_file_path, Path.join(config_path, "deployer_config.ex")},
      {_, release_path} <- {:release_store_path, Path.join(base_path, "release_store")},
      {_, temp_path} <- {:temp_path, Path.join(base_path, "temp")},
      {_, dets_path} <- {:dets_path, Helpers.Paths.build_dets_path(config_path)}
    ) do
      
      %__MODULE__{
        root_path: root_path,
        base_path: base_path,
        config_path: config_path,
        config_file: config_file,
        release_path: release_path,
        temp_path: temp_path,
        dets_path: dets_path
      }
      
    else
      error ->
        {:error, :setting_base_path, error}
    end
  end
end
