defmodule Mix.Tasks.Deployer.Ssh do
  use Mix.Task

  alias Deployer.Env

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  @required_args [:target]

  @shortdoc "Connects to the host under user using the provided key path"
  def run(args \\ []) do
    with(
      {_, %Env{} = ctx} <- {:load_ctx, DH.load_config(args)},
      {_, :ok} <- {:enforce_args, DH.enforce_args(ctx, @required_args)},
      {_, {:ok, conf}} <- {:make_deploy_conf, DH.make_deploy_conf(ctx)},
      {_, {:ok, name}} <- {:connect_ssh, connect_ssh(conf)}
    ) do
      AH.success("Connected to #{conf.host} with user #{conf.user}")
      {:ok, name}
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
      "\\send\n" ->
        file = "/Users/mnussbaumer/code/homelytics_umbrella/deployer/release_store/homelytics-1563658868.tar.gz"
        ref = "1563658868"
        store_dir = "/home/ubuntu/homelytics_deployer"
        Deployer.SSH.upload_release(name, file, store_dir, ref)
        |> IO.inspect(label: "send_file call")
        loop(name)
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
