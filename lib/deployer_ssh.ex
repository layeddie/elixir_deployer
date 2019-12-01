defmodule Deployer.SSH do
  use GenServer
  require Logger

  alias Deployer.Helpers, as: DH
  alias DH.ANSI, as: AH

  @mb_conv 0.00000095367432

  @enforce_keys [:key_path, :host, :user, :ssh]
  defstruct [:key_path, :host, :user, :ssh, :id, pid_mappings: %{}, responses: %{}]

  @default_timeout 60_000 * 25

  defmodule Sendfile do
    @enforce_keys [:size, :file, :dest_folder, :dest_full, :dest, :touch_file, :reply_to, :state, :name]
    defstruct [:size, :file, :dest_folder, :dest_full, :dest, :touch_file, :reply_to, :state, :channel, :name]
  end

  alias __MODULE__.Sendfile

  def start(conf, name) when is_atom(name) do
    GenServer.start(__MODULE__, conf, name: name)
  end

  def stop(name) do
    GenServer.call(name, :exit)
  end

  def execute(command, name, timeout \\ @default_timeout) do
    send(name, {:exec, command, self()})
    receive do
      {:response, response} -> response
    after
      timeout ->
        {:error, :timeout}
    end
  end

  def upload_release(name,
    %Deployer.Release{path: file, ref: ref},
    %Deployer.Configuration.Target{path: path}
  ) do
    upload_release(name, file, path, ref)
  end

  def upload_release(name, file, store_dir, ref) do
    case GenServer.call(name, {:upload_release, file, store_dir, ref}, @default_timeout * 4) do
      {:error, :existing_unfinished_upload, info} ->
        stale_request(name, file, store_dir, ref, info, "Stale upload found. Delete leftovers and retry?")
      {:error, :creating_destination_folder, info, {:error, :failure}} ->
        override?(name, file, store_dir, ref, info, "A folder for this release ref already exists, override?")
      {:ok, info} ->
        {:ok, info}
      error ->
        error
    end
  end

  def stale_request(name, file, store_dir, ref, info, msg) do
    case AH.wait_input("#{msg} [Yn]") do
      "Y" ->
        GenServer.call(name, {:clean_all, info})
        upload_release(name, file, store_dir, ref)
      "n" ->
        {:error, :aborted}
      _ ->
        AH.warn("Please type Y for yes or n for no.")
        stale_request(name, file, store_dir, ref, info, msg)
    end
  end

  def override?(name, file, store_dir, ref, info, msg) do
    case AH.wait_input("#{msg} [Yn]") do
      "Y" ->
        upload_release(name, file, store_dir, ref)
      "n" ->
        {:error, :aborted}
      _ ->
        AH.warn("Please type Y for yes or n for no.")
        stale_request(name, file, store_dir, ref, info, msg)
    end
  end

  def init(conf) do
    host = Map.get(conf, :host)
    user = Map.get(conf, :user)
    port = Map.get(conf, :port, 22)
    access_key = Map.get(conf, :ssh_key)
    
    interactive = Map.get(conf, :interactive)
    case :ssh.start() do
      :ok ->
        key_path = Path.expand(access_key)
        priv_path = Path.join([Application.app_dir(:deployer), "priv", host])
        with(
          {_, :ok} <- {:make_priv_dir, File.mkdir_p(priv_path)},
          {_, priv_key_path} <- {:path_priv_key, Path.join(priv_path, "id_rsa")},
          {_, :ok} <- {:copy_ssh_key_to_priv, File.cp(key_path, priv_key_path)}
        ) do
        
          cl_host = String.to_charlist(host)
          cl_user = String.to_charlist(user)
          cl_priv_key_dir = String.to_charlist(priv_path)

          options = [user: cl_user, silently_accept_hosts: true, user_dir: cl_priv_key_dir]

          try do
            if interactive do
              :ssh.shell(cl_host, port, options)
              {:stop, :interactive}
            else
              case :ssh.connect(cl_host, port, options) do
                {:ok, ref} ->
                  {:ok, %__MODULE__{key_path: cl_priv_key_dir, host: cl_host, user: cl_user, ssh: ref}, {:continue, :open_channel}}
                {:error, reason} ->
                  {:stop, {reason, cl_host, port, cl_user, key_path}}
              end
            end
          after
            File.rm(priv_key_path)
          end
        else
          error ->
            {:stop, error}
        end
      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_continue(:open_channel, %{ssh: ref} = state) do
    {:ok, channel_id} = :ssh_connection.session_channel(ref, 60_000 * 20)
    {:noreply, %{state | id: channel_id}}
  end

  
  #######################################################
  # GenServer Impl
  #######################################################
  
  def handle_info({:exec, command, pid}, %{ssh: ssh, id: id, pid_mappings: pms} = state) do
    case :ssh_connection.exec(ssh, id, command, 150_000) do
      :success ->
        n_pms = Map.put(pms, id, pid)
        {:noreply, %{state | pid_mappings: n_pms}, {:continue, :open_channel}}
      {:error, reason} ->
        :ssh_connection.close(ssh, id)
        if(pid, do: send(pid, {:response, {:error, reason}}))
        {:noreply, %{state | id: nil}, {:continue, :open_channel}}
    end
  end

  def handle_info({:ssh_cm, _, {:exit_status, chan_id, code}}, %{responses: all_resps} = state) do
    {nil, resp} = case Map.fetch(all_resps, chan_id) do
                    {:ok, fetched} -> fetched
                    :error -> {nil, []}
                  end
    n_resps = Map.put(all_resps, chan_id, {code, Enum.reverse(resp) |> List.to_string})
    {:noreply, %{state | responses: n_resps}}
  end

  def handle_info({:ssh_cm, _, {:data, chan_id, _type_code, data}}, %{responses: resps} = state) do
    n_resps =
      case Map.fetch(resps, chan_id) do
        :error -> Map.put(resps, chan_id, {nil, [data]})
        {:ok, {code, e_data}} -> Map.put(resps, chan_id, {code, [data | e_data]})
      end
    {:noreply, %{state | responses: n_resps}}
  end

  def handle_info({:ssh_cm, _, {:eof, _chan_id}}, state) do
    {:noreply, state}
  end

  def handle_info({:ssh_cm, _, {:closed, chan_id}}, %{responses: all_resps, pid_mappings: pms} = state) do
    {resp, n_resps} = Map.pop(all_resps, chan_id)
    {pid, n_pms} = Map.pop(pms, chan_id)

    if(pid, do: send(pid, {:response, resp}))
    
    {:noreply, %{state | responses: n_resps, pid_mappings: n_pms}}
  end

  def handle_info(message, state) do
    Logger.info("SSH Tunnel Recv Unhandled Message: #{inspect message}")
    {:noreply, state}
  end

  def handle_call(:exit, _, %{ssh: ssh} = state) when not is_nil(ssh) do
    :ssh.close(ssh)
    {:stop, :normal, :exited, state}
  end

  def handle_call({:clean_all, %{dest_folder: dest, touch_file: tcf} = info}, _from, %{ssh: ssh, id: id} = state) do
    case :ssh_connection.exec(ssh, id, "rm -rf #{dest} && rm #{tcf}", 20_000) do
      :success -> {:reply, :ok, state, {:continue, :open_channel}}
      error -> {:reply, error, state, {:continue, :open_channel}}
    end
  end

  def handle_call({:upload_release, file, store_dir, ref}, from, state) do
    case File.stat(file, time: :posix) do
      {:error, posix_error} -> {:reply, {:error, :trying_file_stats, posix_error, file}, state}

      {:ok, %File.Stat{size: size, access: access}} when access in [:read, :read_write] ->
        dest = "#{store_dir}/releases/deployer_#{ref}"
        filename = Path.basename(file)
        info =
              %Sendfile{
                size: size,
                file: file,
                name: filename,
                dest: dest,
                dest_full: String.to_charlist("#{dest}/#{filename}"),
                dest_folder: String.to_charlist(dest),
                touch_file: String.to_charlist("#{store_dir}/inprogress_#{ref}"),
                reply_to: from,
                state: :not_started
              }
        
        {:noreply, state, {:continue, {:upload_release, info}}}
      _ ->
        {:reply, {:error, :no_read_access, file}, state}
    end
  end
  
  def handle_continue({:upload_release, info}, %{ssh: ssh, id: id} = state) do
    case :ssh_connection.subsystem(ssh, id, 'sftp', 5000) do
      :success ->
        case :ssh_sftp.start_channel(ssh) do
          {:ok, c_pid} ->
            mb_size = Float.round(info.size * @mb_conv, 2)
            AH.success("Starting upload for #{info.name} (#{mb_size} MB)")
            n_state = %{info | state: :started, channel: c_pid}
            {:noreply, state, {:continue, {:check_touch, n_state}}}
          error ->
            GenServer.reply(info.reply_to, {:error, :starting_channel, error})
            {:noreply, state, {:continue, {:clean_up_channel, info}}}
        end
      error ->
        GenServer.reply(info.reply_to, {:error, :starting_channel, error})
        {:noreply, state, {:continue, {:clean_up_channel, info}}}
    end
  end

  def handle_continue({:check_touch, %{channel: cpid, touch_file: tcf} = info}, state) do
    AH.warn("Checking if has stale/is_uploading")
    case :ssh_sftp.open(cpid, tcf, [:read], 5000) do
      {:ok, file_handle} ->
        AH.warn("Existing unfinished upload for this release.")
        :ssh_sftp.close(cpid, file_handle, 5_000)
        {:no_clean, {:error, :existing_unfinished_upload, info}}
      _error ->
        AH.success("No stale/uploading")
        case :ssh_sftp.open(cpid, tcf, [:creat, :write], 5_000) do
          {false, false, false} ->
            IO.inspect("false false false")
            case :ssh_sftp.open(cpid, tcf, [:write], 5_000) do
              {:ok, file_handle} ->
                case :ssh_sftp.write(cpid, file_handle, ".", 5_000) do
                  :ok ->
                    case :ssh_sftp.close(cpid, file_handle, 5_000) do
                      :ok -> {:ok, {:continue, {:create_dir, info}}}
                      error -> {:error, {:error, :closing_staleness_file, error}}
                    end
                  error ->
                    {:error, :writing_staleness_file, error}
                end
              error ->
                {:error, :opening_staleness_file_to_write, error}
            end
          {:ok, file_handle} ->
            case :ssh_sftp.write(cpid, file_handle, ".", 5_000) do
              :ok ->
                case :ssh_sftp.close(cpid, file_handle, 5_000) do
                  :ok -> {:ok, {:continue, {:create_dir, info}}}
                  error -> {:error, {:error, :closing_staleness_file, error}}
                end
              error ->
                {:error, :writing_staleness_file, error}
            end
          error ->
            {:error, {:error, :opening_staleness_file, error}}
        end
    end
    |> case do
         {:ok, continue} -> {:noreply, state, continue}
         {:error, error} ->
           GenServer.reply(info.reply_to, error)
           {:noreply, state, {:continue, {:clean_up_touch, info}}}
         {:no_clean, error} ->
           GenServer.reply(info.reply_to, error)
           {:noreply, state, {:continue, {:clean_up_channel, info}}}
       end
  end

  def handle_continue({:create_dir, %{channel: cpid, dest_folder: dest_folder, dest: dest} = info}, state) do
    case :ssh_sftp.make_dir(cpid, dest_folder, 50_000) do
      :ok ->
        AH.success("Created folder for upload at #{dest}")
        {:noreply, state, {:continue, {:upload, %{info | state: :uploading}}}}
      error ->
        GenServer.reply(info.reply_to, {:error, :creating_destination_folder, info, error})
        {:noreply, state, {:continue, {:clean_up_touch, info}}}
    end
  end

  def handle_continue(
    {:upload, %{channel: cpid, dest_full: dest_full, file: file, size: size} = info},
    state
  ) do
    chunks = 200_000
    printer_pid = spawn(__MODULE__, :printer, [size, chunks])
    stream = File.stream!(file, [], chunks)

    case :ssh_sftp.open(cpid, dest_full, [:creat, :write], 100_000) do
      {:ok, handle} ->
        start_time = :erlang.monotonic_time()
        stream
        |> Stream.map(fn(data) ->
          case :ssh_sftp.write(cpid, handle, data) do
            :ok ->
              send(printer_pid, 1)
              :ok
            error ->
              send(printer_pid, {:error, error})
              AH.error("Error when streaming file: #{inspect error}")
              error
          end
        end)
        |> Stream.take_while(&(&1 == :ok))
        |> Stream.drop_while(&(&1 == :ok))
        |> Stream.run()
        |> case do
             :ok ->
               elapsed = (:erlang.convert_time_unit((:erlang.monotonic_time() - start_time), :native, :millisecond) / 1000)
               send(printer_pid, {:error?, self()})
               receive do
                 {:printer, :noop} ->
                   IO.write(IO.ANSI.clear_line() <> IO.ANSI.cursor_left(4) <> IO.ANSI.cursor_up(1) <> IO.ANSI.clear_line())
                   AH.success("Uploaded in #{elapsed} s")
                   Process.exit(printer_pid, :kill)
                   GenServer.reply(info.reply_to, {:ok, info})
                   {:noreply, state, {:continue, {:clean_up_touch, info}}}
                 {:printer, error} ->
                   Process.exit(printer_pid, :kill)
                   GenServer.reply(info.reply_to, {:error, :streaming_file, error})
                   {:noreply, state, {:continue, {:clean_up_dest, info}}}
               after
                 60_000 ->
                   Process.exit(printer_pid, :kill)
                   GenServer.reply(info.reply_to, {:error, :streaming_file})
                   {:noreply, state, {:continue, {:clean_up_dest, info}}}
               end
           end

      error ->
        GenServer.reply(info.reply_to, {:error, :writing_file, error})
        {:noreply, state, {:continue, {:clean_up_dest, info}}}
    end
  end
  
  def handle_continue({:clean_up_touch, %{channel: cpid, touch_file: tcf} = info}, state) do
    :ssh_sftp.delete(cpid, tcf)
    {:noreply, state, {:continue, {:clean_up_channel, info}}}
  end
  
  def handle_continue({:clean_up_dest, %{dest_folder: dest_folder, touch_file: tcf} = info}, state) do
    send(self(), {:exec, "rm -rf #{dest_folder} && rm #{tcf}", nil})
    {:noreply, state, {:continue, {:clean_up_channel, info}}}
  end
  
  def handle_continue({:clean_up_channel, %{channel: cpid}}, state) do
    :ssh_sftp.stop_channel(cpid)
    {:noreply, state, {:continue, :open_channel}}
  end
  
  def printer(size, chunks) do
    AH.warn("Starting upload...")
    print_start(0, size, chunks)
  end
  
  def print_start(done, total, chunk_size) do
    percent =
      case done * 100 / total do
        n when n > 100 -> 100
        n -> n
      end
    IO.write(IO.ANSI.clear_line() <> IO.ANSI.cursor_left(4) <> "#{round(percent)}%")
    receive do
      1 -> print_start(done + chunk_size, total, chunk_size)
      {:error, error} ->
        receive do
          {:error?, pid} -> send(pid, {:printer, error})
        after
          240_000 -> :ok
        end
      {:error?, pid} -> send(pid, {:printer, :noop})
    after
      240_000 -> :ok
    end
  end
end
