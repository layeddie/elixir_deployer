defmodule Deployer.SSH do
  use GenServer
  require Logger

  @enforce_keys [:key_path, :host, :user, :ssh]
  defstruct [:key_path, :host, :user, :ssh, :id, pid_mappings: %{}, responses: %{}]

  @default_timeout 60_000 * 5

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
      timeout -> {:error, :timeout}
    end
  end

  def init(conf) do
    host = Keyword.get(conf, :host)
    user = Keyword.get(conf, :user)
    port = Keyword.get(conf, :port, 22)
    interactive = Keyword.get(conf, :interactive)
    access_key = Keyword.get(conf, :ssh_key)
    case :ssh.start() do
      :ok ->
        key_path = Path.expand(access_key)
        priv_path = Path.join(Application.app_dir(:deployer), "priv")
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
    {:ok, channel_id} = :ssh_connection.session_channel(ref, 20_000)
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
        send(pid, {:response, {:error, reason}})
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

  def handle_call(:exit, _, state) do
    {:stop, :normal, :exited, state}
  end
end
