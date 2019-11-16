defmodule Mix.Tasks.Deployer.Build do
  use Mix.Task

  alias Deployer.Release, as: Rel
  alias Deployer.Env
  
  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  @type valid_build :: {%Env{}, %Rel{}} | :halt | {:halt, atom, atom, list}

  @required_args [:target]

  def run(args \\ []) do
    try do
      with(
        {_, %Env{} = ctx} <- {:load_ctx, DH.load_config(args)},
        {_, :ok} <- {:enforce_args, DH.enforce_args(ctx, @required_args)},
        {_, {:ok, builder}} <- {:check_if_has_builder, DH.decide_builder(ctx)},
        {_, {%Env{} = ctx_2, %Rel{path: path} = res}} <- {:run_build, run_build(builder, ctx)},
        {_, :ok} <- {:ensure_gzip_exists, ensure_gzipped_file_exists(path)},
        {_, :ok} <- {:writing_release_to_store, DH.DETS.add_release(res, ctx_2)}
      ) do
        AH.success("Builder completed")
        {:ok, ctx_2}
      else
        return_value -> check_return_value(return_value)
      end
    after
      DH.DETS.close()
    end
  end

  @spec check_return_value({:run_build, valid_build} | {:run_build, any()}) :: {:ok, %Env{}} | any()
  defp check_return_value(value) do
    case value do
      {:run_build, {:halt, ctx}} ->
        AH.success("Builder completed")
        {:ok, ctx}
        
      {:run_build, {:halt, m, f, a}} ->
        case apply(m, f, a) do
          {%Env{} = ctx_2, %Deployer.Release{path: path} = res} ->
            case ensure_gzipped_file_exists(path) do
              :ok ->
                DH.DETS.add_release(res, ctx_2)
                AH.success("Builder completed")
                {:ok, ctx_2}
              error ->
                AH.error("Couldn't find a finished file on path: #{inspect path}")
                error
            end
          {:ok, %Env{} = ctx_2} ->
            AH.success("Builder completed")
            {:ok, ctx_2}
          error -> {:error, error}
        end
      error ->
        AH.error(error)
        {:error, error}
    end
  end

  @spec run_build({atom, atom, list()}, %Env{}) :: valid_build | any()
  defp run_build({m, f, a}, ctx), do: apply(m, f, [ctx | a])

  @spec ensure_gzipped_file_exists(String.t) :: :ok | {:file_doesnt_exist, String.t}
  defp ensure_gzipped_file_exists(path) do
    case File.exists?(path) do
      true -> :ok
      _ -> {:file_doesnt_exist, path}
    end
  end
end
