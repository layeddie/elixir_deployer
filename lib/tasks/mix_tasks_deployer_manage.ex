defmodule Mix.Tasks.Deployer.Manage do
  use Mix.Task

  alias Deployer.Release, as: Rel
  alias Deployer.Env

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  alias Deployer.SSH

  @commands %{
    "info" => %{
  cmd: "info [ref]",
  description: "shows general local info, or info for the release `ref` if specified",
  fun: {__MODULE__, :info}
},
    "h" => %{
      cmd: "h",
      description: "show available commands",
      fun: {__MODULE__, :help}
    },
    "prune" => %{
      cmd: "prune name",
      description: "removes all releases and tarballs with name `name` except for that tagged `latest`",
      fun: {__MODULE__, :prune}
    },
    "\\q" => %{
      cmd: "\\q",
      description: "quit the manager",
      fun: {__MODULE__, :quit}
    },
    "delete" => %{
      cmd: "delete ref",
      description: "deletes the release with `ref` from the local store and any associated tarballs",
      fun: {__MODULE__, :delete}
    },
    "connect" => %{
      cmd: "connect target",
      description: "connect to remote `target` defined in the deployer configuration (uses SSH, the configuration has to have all required details)",
      fun: {__MODULE__, :connect}
    }
  }

  @required_args [:target]

  @shortdoc "Connects to the host to do managing operations - cleaning releases, changing the symlinks, etc"
  def run(args \\ []) do
    try do
      with(
        {_, %Env{} = ctx} <- {:load_ctx, DH.load_config(args)},
        {_, :ok} <- {:output_info, AH.info("\n\n>>>>>> Managing Local Store")},
        {_, {:ok, releases}} <- {:get_local_releases, DH.DETS.get_existing_releases(ctx)},
        {_, :ok} <- {:print_info, print_info(ctx, releases)},
        {_, :ok} <- {:loop, enter_loop(ctx, releases)}
      ) do
        AH.success("Finished.")
      else
        {:loop, {:switch, n_ctx}} ->
          Mix.Tasks.Deployer.Manage.Remote.run(n_ctx)
        error -> AH.error(error)
      end
    after
      DH.DETS.close()
    end
  end

  defp print_info(ctx, releases) do
    info(ctx, releases, nil)
    :ok
  end

  def enter_loop(ctx, releases) do
    print_commands()
    loop(ctx, releases)
  end

  defp loop(ctx, releases) do
    AH.wait_input(">")
    |> command(ctx, releases)
    |> case do
         :ok -> :ok
         {:loop, {n_ctx, n_releases}} -> loop(n_ctx, n_releases)
         error -> error
       end
  end

  Enum.each(@commands, fn({k, %{fun: {m,f}}}) ->
    def command(<<unquote(k), rem::binary>>, ctx, releases), do: apply(unquote(m), unquote(f), [ctx,releases, String.trim(rem)])
  end)

  def command(cmd, ctx, releases) do
    AH.error("Invalid command #{cmd}")
    enter_loop(ctx, releases)
  end

  defp print_commands() do
    AH.info("Available commands:\n")
    Enum.each(@commands, fn({_k, %{cmd: cmd, description: desc}}) ->
      AH.info_command(cmd, desc)
    end)
    IO.write("\n")
  end

  def info(
    ctx,
    releases,
    _
  ) do
    case releases do
      [] -> AH.warn("\n\nNo releases available")
      _ ->
        IO.write("\n\nAvailable Releases\n\n")
        Enum.each(releases, fn(%{name: name, tags: tags, created_at: ca, ref: ref}) ->
          IO.write(IO.ANSI.yellow() <> "#{name}")
          AH.info_command("ref: #{ref}", "#{DateTime.to_string(ca)} - tags: #{Enum.join(tags, ", ")}")
        end)
        IO.puts(IO.ANSI.default_color())
    end

    case DH.extract_valid_targets(ctx) do
      [] -> AH.warn("\nNo currently defined targets")
      targets ->
        IO.write(IO.ANSI.magenta() <> "\nConfigured Targets:\n\n")
        Enum.each(targets, fn({k, host, user, name}) ->
          IO.write(IO.ANSI.magenta() <> "#{k}")
          AH.info_command("#{host}", "user: #{user}, release name: #{name}")
        end)
        IO.puts(IO.ANSI.default_color())
    end
    {:loop, {ctx, releases}}
  end

  def quit(_, _, _), do: :ok

  def help(ctx, releases, _), do: enter_loop(ctx, releases)

  def remove_release(%{ref: ref, name: rel_name, path: path}) do
    case File.rm_rf(path) do
      {:ok, _} ->
        AH.warn(">> Removed #{rel_name} tar, with ref #{ref}")
        :ok
      error ->
        AH.error("Error removing #{rel_name} with ref #{ref}\n >> #{inspect error}\n")
        error
    end
  end

  def prune(ctx, releases, t_name) do
    n_releases =
      Enum.reduce(releases, [], fn(%{name: name, ref: ref, tags: tags} = rel, acc) ->
        case name == t_name and "latest" not in tags do
          true ->
            case remove_release(rel) do
              :ok -> acc
              {:error, error, _} -> [rel | acc]
            end
          false -> [rel | acc]
        end
      end)

    case DH.DETS.write_releases(n_releases, ctx) do
      {:ok, _} -> {:loop, {ctx, n_releases}}
      error -> error
    end
  end

  def connect(ctx, releases, target) do
    n_ctx = DH.put_env(ctx, :target, target)
    case DH.make_deploy_conf(n_ctx) do
      {:missing_target_config_for, ^target} ->
        AH.warn("Invalid target...")
        {:loop, {ctx, releases}}
      _ ->
        {:switch, n_ctx}
    end
  end
end
    
