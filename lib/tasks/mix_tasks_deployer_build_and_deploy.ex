defmodule Mix.Tasks.Deployer.BuildAndDeploy do
  use Mix.Task

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH
  require AH

  @required_args_1 [:target]
  @required_args_or_2 [:group]
  @required_args {[@required_args_1, @required_args_or_2]}

  @shortdoc "Builds & Deploys a Release"
  def run(args \\ []) do
    # for the case when the task crashes and doesn't clean up, we force clean the temp folder

    with(
      {_, :ok} <- {:set_deployer_paths, DH.Paths.set_deployer_paths()},
      {_, true} <- {:deployer_init?, DH.Paths.is_initialised?()},
      {_, :ok} <- {:parsing_args, DH.args_into_pterms(args)},
      {_, :ok} <- {:enforce_args, DH.enforce_args(@required_args)},
      {_, :ok} <- {:add_names, DH.maybe_create_essential()},
      {_, :ok} <- {:run_builder, Mix.Task.run(:"deployer.builder")},
      {_, :ok} <- {:run_deployer, Mix.Task.run(:"deployer.deploy")}
    ) do
      AH.success("Finished Build and Deploy")
      :ok
    else
      error ->
        AH.error("Deployer Error: #{inspect error}")
    end
  end
end
