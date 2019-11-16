defmodule Mix.Tasks.Deployer.BuildAndDeploy do
  use Mix.Task

  alias Deployer.Env

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  @required_args [:target]

  @shortdoc "Builds & Deploys a Release"
  def run(args \\ []) do
    try do
      with(
        {_, %Env{} = ctx} <- {:load_ctx, DH.load_config(args)},
        {_, :ok} <- {:enforce_args, DH.enforce_args(ctx, @required_args)},
        {_, {:ok, n_ctx}} <- {:run_builder, Mix.Task.run(:"deployer.build", ctx)},
        {_, {:ok, n_ctx_2}} <- {:run_deployer, Mix.Task.run(:"deployer.deploy", n_ctx)}
      ) do
        AH.success("Finished Build and Deploy")
        {:ok, n_ctx_2}
      else
        error ->
          AH.error("Deployer Error: #{inspect error}")
      end
    after
      DH.DETS.close()
    end
  end
end
