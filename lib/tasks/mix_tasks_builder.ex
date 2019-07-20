defmodule Mix.Tasks.Deployer.Builder do
  use Mix.Task
  
  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH
  require AH
  
  @default_builder %{module: Deployer.Docker.Builder, function: :build, args: []}

  @required_args [:builder]

  def run(args \\ []) do
    with(
      {_, :ok} <- {:set_deployer_paths, DH.Paths.set_deployer_paths()},
      {_, true} <- {:deployer_init?, DH.Paths.is_initialised?()},
      {_, :ok} <- {:parsing_args, DH.args_into_pterms(args)},
      {_, :ok} <- {:enforce_args, DH.enforce_args(@required_args)},
      {_, :ok} <- {:add_names, DH.maybe_create_essential()},
      {_, :ok} <- {:create_temp_folder, create_temp_folder()},
      {_, :ok} <- {:include_env_file, maybe_include_environment_file()},
      {_, :ok} <- {:pre_build_step, maybe_has_pre_build_step()},
      {_, %Deployer.Release{path: path} = res} <- {:run_build, run_build()},
      {_, :ok} <- {:ensure_gzipped_file_exists, ensure_gzipped_file_exists(path)}
    ) do
      clean_temp()
      store_result(res)
      AH.success("Builder completed")
      :ok
    else
      return_value -> check_return_value(return_value)
    end
  end

  defp check_return_value(value) do
    case value do
      {:run_build, :halt} ->
        clean_temp()
        AH.success("Builder completed")
        :ok
        
      {:run_build, {:halt, m, f, a}} ->
        case apply(m, f, a) do
          %Deployer.Release{path: path} = res ->
            case ensure_gzipped_file_exists(path) do
              :ok ->
                clean_temp()
                store_result(res)
                AH.success("Builder completed")
                :ok
              error ->
                AH.error("Couldn't find a finished file on path: #{inspect path}")
                error
            end
          :ok ->
            clean_temp()
            AH.success("Builder completed")
            :ok
          error ->
            clean_temp()
            {:error, error}
        end
      error ->
        clean_temp()
        AH.error(error)
        {:error, error}
    end
  end

  defp run_build do
    case DH.read_env(:builder) do
      nil -> apply(@default_builder[:module], @default_builder[:function], @default_builder[:args])
      mfa_bin when is_binary(mfa_bin) -> DH.apply_mfa_bin(mfa_bin)
    end
  end

  defp create_temp_folder do
    path = DH.read_env(:deployer_temp_path)

    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, posix_error} -> {:error_posix, posix_error}
    end
  end

  defp clean_temp do
    path = DH.read_env(:deployer_temp_path)
    File.rm_rf(path)
  end

  defp maybe_include_environment_file do
    case DH.read_env(:env_file) do
      nil -> :ok
      path ->
        environment_file = Path.basename(path)
        case File.cp_r(Path.expand(path), Path.join(DH.read_env(:deployer_temp_path), environment_file)) do
          {:ok, _} -> DH.put_env(:env_file_name, environment_file)
          {:error, error_code, _} -> {:error_including_environment_file, :posix_result, error_code}
        end
    end
  end

  defp maybe_has_pre_build_step do
    case DH.read_env(:pre_build_step) do
      nil -> :ok
      mfa_bin -> DH.apply_mfa_bin(mfa_bin)
    end
  end

  defp ensure_gzipped_file_exists(path) do
    case File.exists?(path) do
      true -> :ok
      _ -> {:file_doesnt_exist, path}
    end
  end

  def store_result(%Deployer.Release{} = result) do
    case DH.DETS.open_dets_table(true) do
      {:ok, dets} ->
        existing =
          case :dets.lookup(dets, :available_releases) do
            [{_, existing}] -> existing
            _ -> []        
          end

        id = DH.DETS.get_and_update_counter(true)
        
        :dets.insert(dets, {:available_releases, [%{result | id: id} | existing]})
        DH.DETS.close()
      error -> error
    end
  end
end
