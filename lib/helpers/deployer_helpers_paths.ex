defmodule Deployer.Helpers.Paths do
  
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
