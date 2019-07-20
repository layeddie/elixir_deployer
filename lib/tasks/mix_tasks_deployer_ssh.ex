defmodule Mix.Tasks.Deployer.Ssh do
  use Mix.Task

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH
  require AH

  @required_args_1 [:target]
  @required_args_or_2 [:host, :user, :ssh_key, :path]
  @required_args {[@required_args_1, @required_args_or_2]}

  @shortdoc "Connects to the host under user using the provided key path"
  def run(args \\ []) do
    with(
      {_, :ok} <- {:set_deployer_paths, DH.Paths.set_deployer_paths()},
      {_, :ok} <- {:parsing_args, DH.args_into_pterms(args)},
      {_, :ok} <- {:enforce_args, DH.enforce_args(@required_args)},
      {_, :ok} <- {:add_names, DH.maybe_create_essential()},
      {_, {:ok, conf}} <- {:make_deploy_conf, DH.make_deploy_conf()},
      {_, {:ok, name}} <- {:connect_ssh, connect_ssh(conf)}
    ) do
      AH.success("Connected to #{inspect conf}, type \exit to quit")
      {:ok, name}
      #loop(name)
    else
      error ->
        AH.error("Deployer SSH Error: #{inspect error}")
      {:error, error}
    end
  end

  defp connect_ssh(conf) do
    rand_id = (:crypto.strong_rand_bytes(4) |> Base.encode16)
    name = String.to_atom("ssh_#{rand_id}")

    case Deployer.SSH.start(conf, name) do
      {:ok, _} -> {:ok, name}
      error -> error
    end
  end

  defp loop(name) do
    case AH.wait_input("> ") do
      "\\exit\n" ->
        stop(name)
      command  ->
        case Deployer.SSH.execute(command, name) do
          {:error, :timeout} -> :ok
          {_code, response} ->
            AH.response(String.split(response, "\n"))
            loop(name)
        end
    end
  end

  defp stop(name) do
    spawn(fn() -> Deployer.SSH.stop(name) end)
  end
end
