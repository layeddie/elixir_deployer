defmodule Deployer.Helpers.Paths do
  alias Deployer.Helpers, as: DH
  alias Deployer.Configuration.Context, as: CTX

  require DH.ANSI

  def is_initialised? do
    case DH.read_env(:deployer_config_file) do
      path when is_binary(path) -> File.exists?(path)
      _ -> false
    end
  end
  
  def set_deployer_paths do
    if DH.read_env(:deployer_paths_set) do
      :ok
    else
      
      with(
        {_, root_path} when is_binary(root_path) <- {:root_path, get_root_path()},
        {_, true} <- {:root_path_exists, File.exists?(root_path)},
        {_, deployer_path} <- {:deployer_path, Path.join(root_path, "deployer")},
        {_, config_path} <- {:config_path, Path.join(deployer_path, "config")},
        {_, config_file_path} <- {:config_file_path, Path.join(config_path, "deployer_config.ex")},
        {_, release_path} <- {:release_store_path, Path.join(deployer_path, "release_store")},
        {_, temp_path} <- {:temp_path, Path.join(deployer_path, "temp")},
        {_, dets_path} <- {:dets_path, build_dets_path(config_path)}
      ) do
        DH.put_env(:deployer_root_path, root_path)
        DH.put_env(:deployer_path, deployer_path)
        DH.put_env(:deployer_config_path, config_path)
        DH.put_env(:deployer_config_file, config_file_path)
        DH.put_env(:deployer_release_path, release_path)
        DH.put_env(:deployer_temp_path, temp_path)
        DH.put_env(:deployer_dets_path, dets_path)
        case File.exists?(config_file_path) do
          true -> case Code.eval_file("deployer_config.ex", config_path) do
                    {config, _} ->
                      case CTX.create_configuration(config) |> IO.inspect() do
                        {:ok, n_config} -> DH.put_env(:deployer_config, n_config)
                        {:error, changeset} ->
                          DH.ANSI.warn("Invalid Config: #{inspect changeset}")
                      end
                    _ -> :noop
                  end
          _ -> :noop
        end
        DH.put_env(:deployer_paths_set, true)
      else
        error ->
          {:error, :setting_base_paths, error}
      end
      
    end
  end

  defp build_dets_path(config_path) do
    config_path
    |> DH.DETS.path()
    |> String.to_charlist()
  end
  
  def get_root_path do
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

  def get_root_path! do
    case get_root_path() do
      path when is_binary(path) -> path
      error -> raise "Invalid Root Path: #{inspect error}"
    end
  end
  
end
