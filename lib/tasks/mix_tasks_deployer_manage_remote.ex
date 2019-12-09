defmodule Mix.Tasks.Deployer.Manage.Remote do
  use Mix.Task

  alias Deployer.Release, as: Rel
  alias Deployer.Env

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  alias Deployer.SSH

  @commands %{
    "info" => %{
  cmd: "info [ref]",
  description: "shows general remote info, or info for the release `ref` if specified",
  fun: {__MODULE__, :info}
},
    "h" => %{
      cmd: "h",
      description: "show available commands",
      fun: {__MODULE__, :help}
    },
    "prune" => %{
      cmd: "prune name",
      description: "removes all releases and folders with name `name` except for that tagged `latest` (and the current symlinked one)",
      fun: {__MODULE__, :prune}
    },
    "ln" => %{
      cmd: "ln ref",
      description: "changes the current symlinked directory to point to the release with ref `ref`",
      fun: {__MODULE__, :link}
    },
    "integrity" => %{
      cmd: "integrity [-f]",
      description: "does an integrity check on the symlinked folder, and checks all remote releases to see if they appear ready to be used, if `-f` is specified removes any non-existing releases from the remote store",
      fun: {__MODULE__, :integrity}
    },
    "\\q" => %{
      cmd: "\\q",
      description: "quit the manager",
      fun: {__MODULE__, :quit}
    },
    "delete" => %{
      cmd: "delete ref",
      description: "deletes the release with `ref` from the remote and any associated folders",
      fun: {__MODULE__, :delete}
    },
    "local" => %{
      cmd: "local",
      description: "changes to the local manager",
      fun: {__MODULE__, :local}
    }
  }

  @required_args [:target]

  @shortdoc "Connects to the host to do managing operations - cleaning releases, changing the symlinks, etc"
  def run(args \\ []) do
    with(
      {_, %Env{} = ctx} <- {:load_ctx, DH.load_config(args)},
      {_, :ok} <- {:enforce_args, DH.enforce_args(ctx, @required_args)},
      {_, {:ok, conf}} <- {:make_deploy_conf, DH.make_deploy_conf(ctx)},
      {_, {:ok, name}} <- {:try_ssh_connect, Mix.Tasks.Deployer.Ssh.run(ctx)},
      {_, {:ok, remote_info}} <- {:create_remote?, DH.Remote.maybe_create_remote(conf, name)},
      {_, :ok} <- {:print_info, print_info(remote_info)},
      {_, :ok} <- {:loop, enter_loop(ctx, conf, remote_info, name)},
      _ <- SSH.stop(name)
    ) do
      AH.success("Finished.")
    else
      {:loop, {:switch, name}} ->
        SSH.stop(name)
        Mix.Tasks.Deployer.Manage.run([])
      error -> AH.error(error)
    end
  end

  defp print_info(remote_info) do
    info(nil, nil, remote_info, nil, nil)
    :ok
  end

  def enter_loop(ctx, conf, remote_info, name) do
    print_commands()
    loop(ctx, conf, remote_info, name)
  end

  defp loop(ctx, conf, remote_info, name) do
    AH.wait_input(">")
    |> command(ctx, conf, remote_info, name)
    |> case do
         :ok -> :ok
         {:loop, {n_ctx, n_conf, n_rinfo, name}} -> loop(n_ctx, n_conf, n_rinfo, name)
         error -> error
       end
  end

  Enum.each(@commands, fn({k, %{fun: {m,f}}}) ->
    def command(<<unquote(k), rem::binary>>, ctx, conf, rinfo, name), do: apply(unquote(m), unquote(f), [ctx, conf, rinfo, name, String.trim(rem)])
  end)

  def command(cmd, ctx, conf, rinfo, name) do
    AH.error("Invalid command #{cmd}")
    enter_loop(ctx, conf, rinfo, name)
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
    conf,
    %{
      releases: releases,
      current_symlink: %{name: cs_name, tags: cs_tags, created_at: cs_ca, ref: cs_ref}
    } = rinfo,
    name,
    _
  ) do
    rels = Enum.reject(releases, fn(%{ref: ref}) -> ref == cs_ref end)
    IO.write("\n\nCurrent Symlinked" <> IO.ANSI.green())
    AH.info_command("#{cs_name} << ref: #{cs_ref}", "#{DateTime.to_string(cs_ca)} - #{Enum.join(cs_tags, ", ")}")


    case rels do
      [] -> AH.warn("\n\nNo other releases")
      _ -> AH.warn("\n\nOther Releases:\n")
    end
    
    Enum.each(rels, fn(%{name: name, tags: tags, created_at: ca, ref: ref}) ->
      IO.write(IO.ANSI.yellow() <> "#{name}")
      AH.info_command("ref: #{ref}", "#{DateTime.to_string(ca)} - tags: #{Enum.join(tags, ", ")}")
    end)
    IO.puts(IO.ANSI.default_color())
    {:loop, {ctx, conf, rinfo, name}}
  end

  def info(ctx, conf, %{releases: rels} = rinfo, name, _) do
    AH.error("\n\nNo current active release!\n\n")
    Enum.each(rels, fn(%{name: name, tags: tags, created_at: ca, ref: ref}) ->
      IO.write(IO.ANSI.yellow() <> "#{name}")
      AH.info_command("ref: #{ref}", "#{DateTime.to_string(ca)} - tags: #{Enum.join(tags, ", ")}")
    end)
    IO.puts(IO.ANSI.default_color())
    {:loop, {ctx, conf, rinfo, name}}
  end

  def quit(_, _, _, _, _), do: :ok

  def help(ctx, conf, rinfo, name, _), do: enter_loop(ctx, conf, rinfo, name)

  def link(
    ctx,
    %{path: store} = conf,
    %{current_symlink: cs, releases: rels} = remote_info,
    name,
    t_ref,
    force \\ false
  ) do
    
    with(
      {_, true} <- {:is_different_than_symlink, (!cs || cs.ref != t_ref || force)},
    {_, _, %Rel{} = rel} <- {:find_release, t_ref, Enum.find(rels, fn(%{ref: ref}) -> t_ref == ref end)},
      {_, {:ok, path}} <- {:check_integrity, check_integrity(store, rel, name, nil)},
      {_, {:ok, n_rinfo}} <- {:symlink, DH.Remote.symlink(path, remote_info, rel, name)},
      {_, {:ok, _}} <- {:update_remote, DH.Remote.write_remote_config(n_rinfo, store, name)}
    ) do
      AH.success("Successfully updated remote symlink to #{rel.name} (ref: #{rel.ref})")
      {:loop, {ctx, conf, n_rinfo, name}}
    else
      {:is_different_than_symlink, _} ->
        case AH.wait_input("The target release is already given as linked. Relink? [Yn]") do
          "Y" -> link(ctx, conf, remote_info, name, t_ref, true)
          _ -> {:loop, {ctx, conf, remote_info, name}}
        end
      {:check_integrity, _} ->
        AH.error("\nIt seems this release no longer exists.\n")
        {:loop, {ctx, conf, remote_info, name}}
      error -> error
    end
  end

  def check_integrity(store_path, %{ref: ref, name: rel_name}, name, %{ref: ref}) do
    %{rel_path: rel_path, rel_base: rel_base} = DH.Remote.build_paths(store_path, ref, rel_name)
    case SSH.execute("
    test -d #{rel_path} && \
    test -e #{rel_base}/bin/#{rel_name} && \
    test -d #{rel_base}/releases && \
    test -d #{rel_base}/lib && \
    #{rel_base}/bin/#{rel_name} version && \
    readlink #{store_path}/releases/current | grep 'deployer_#{ref}' > /dev/null || exit 3
    ", name) do
      {0, _} -> {:ok, rel_path}
      {3, _} ->
        AH.warn("Current symlinked file in store doesn't match the actual symlink in the system. Do you want to treat it as invalid? If you're running with -f, YES will delete the release. [YES n]")
        case AH.wait_input(">") do
          "YES" -> :mark_as_invalid
          _ -> {:ok, rel_path}
        end
      error -> error
    end
  end

  def check_integrity(store_path, %{ref: ref, name: rel_name}, name, _) do
    %{rel_path: rel_path, rel_base: rel_base} = DH.Remote.build_paths(store_path, ref, rel_name)
    case SSH.execute("
    test -d #{rel_path} && \
    test -e #{rel_base}/bin/#{rel_name} && \
    test -d #{rel_base}/releases && \
    test -d #{rel_base}/lib && \
    #{rel_base}/bin/#{rel_name} version
    ", name) do
      {0, _} -> {:ok, rel_path}
      error -> error
    end
  end

  def integrity(
    ctx,
    %{path: store} = conf,
    %{current_symlink: cs, releases: rels} = rinfo,
    name,
    force
  ) do
    force = is_force?(force)
    
    {cs_invalid, non_valid} =
      Enum.reduce(rels, {false, []}, fn(rel, {is_cs_inv, acc}) ->
        case check_integrity(store, rel, name, cs) do
          {:ok, _} -> {is_cs_inv, acc}
          _ ->
            case rel.ref == cs.ref do
              true -> {true, acc}
              false -> {is_cs_inv, [rel | acc]}
            end
        end
      end)

    case {cs_invalid, non_valid} do
      {false, []} ->
        AH.success("No invalid releases found.")
        {:loop, {ctx, conf, rinfo, name}}
      _ -> 
        output_invalid_releases(cs_invalid, non_valid, cs)                
        case force do
          true ->
            case remove_invalid_releases(cs_invalid, non_valid, ctx, conf, rinfo, name) do
              {:ok, n_rinfo} -> {:loop, {ctx, conf, n_rinfo, name}}
              error -> error
            end
          false ->
            {:loop, {ctx, conf, rinfo, name}}
        end
    end
  end

  def is_force?("-f"), do: true
  def is_force?(_), do: false

  def output_invalid_releases(cs_invalid, invalid, cs) do
    if cs_invalid do
      AH.error("\n>>>>>> Current symlinked release is invalid!\n")
      output_release(cs)
      AH.error("\n<<<<<<")
    end
    IO.write("\n")
    case invalid do
      [] -> :ok
      _ ->
        AH.warn("Invalid Releases >>>>>>")
        Enum.each(invalid, fn(rel) -> output_release(rel) end)
        AH.warn("<<<<<<")
    end
  end

  def output_release(%{name: n, ref: ref, created_at: cat, tags: tags}) do
    AH.info_command("#{n} << ref: #{ref}", "#{DateTime.to_string(cat)} - #{Enum.join(tags, ", ")}")
  end

  def remove_invalid_releases(cs_invalid, invalid,
    _ctx, %{path: store} = conf, %{current_symlink: cs, releases: rels} = rinfo, name) do
    to_remove = if(cs_invalid, do: [cs | invalid], else: invalid)
    
    remd =
      Enum.reduce(to_remove, [], fn(%{ref: ref, name: rel_name} = rel, acc) ->
        case remove_release(rel, conf, name) do
          {:ok, removed_ref} -> [removed_ref | acc]
          _ -> acc
        end
      end)
    
    wo_rem = Enum.reject(rels, fn(%{ref: ref}) -> ref in remd end)
    n_rinfo = %{rinfo | releases: wo_rem, current_symlink: if(cs.ref in remd, do: false, else: cs)}

    case cs.ref in remd do
      true -> AH.warn("\n>>>>>> Currently no symlinked folder exists!!! <<<<<<\n")
      _ -> :noop
    end

    DH.Remote.write_remote_config(n_rinfo, store, name)
  end

  def remove_release(%{ref: ref, name: rel_name}, %{path: store_path} = conf, name) do
    %{rel_path: rel_path} = DH.Remote.build_paths(store_path, ref, rel_name)
    case SSH.execute("rm -rf #{rel_path}", name) do
      {0, _} ->
        AH.warn(">> Removed #{rel_name} with ref #{ref}")
        {:ok, ref}
      error ->
        AH.error("Error removing #{rel_name} with ref #{ref}\n >> #{inspect error}\n")
        error
    end
  end

  def delete(ctx, conf, %{current_symlink: cs, releases: rels} = rinfo, name, t_ref) do
    cs_ref = if(cs, do: cs.ref)

    to_rem =
      Enum.reduce(rels, [], fn(%{ref: ref} = rel, acc) ->
        case t_ref == ref and ref != cs_ref do
          true -> [rel | acc]
          false ->
            case ref == cs_ref do
              true -> AH.warn("\n>>>>>> You're trying to remove the currently symlinked release!!! <<<<<<\n")
              _ -> :ok
            end
            acc
        end
      end)

    case remove_invalid_releases(false, to_rem, ctx, conf, rinfo, name) do
      {:ok, n_rinfo} -> {:loop, {ctx, conf, n_rinfo, name}}
      error -> error
    end
  end

  def prune(ctx, conf, %{current_symlink: cs, releases: rels} = rinfo, name, t_name) do
    cs_ref = if(cs, do: cs.ref)

    to_rem =
      Enum.reduce(rels, [], fn(%{name: name, ref: ref} = rel, acc) ->
        case name == t_name and ref != cs_ref do
          true -> [rel | acc]
          false -> acc
        end
      end)

    case remove_invalid_releases(false, to_rem, ctx, conf, rinfo, name) do
      {:ok, n_rinfo} -> {:loop, {ctx, conf, n_rinfo, name}}
      error -> error
    end
  end

  def local(_ctx, _conf, _rinfo, name, _) do
    {:switch, name}
  end
end
    
