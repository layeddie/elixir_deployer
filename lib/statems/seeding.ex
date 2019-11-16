defmodule Seeding do
  @behaviour :gen_statem

  require Logger

  alias Deployer.Helpers, as: DH

  @enforce_keys [:ctx]
  defstruct [
    :ctx,
    :conf,
    :server_id,
    :key_path,
    :host,
    :user,
    :ssh,
    result: :loading
  ]

  @impl :gen_statem
  def callback_mode(), do: :handle_event_function

  def start(ctx) do
    :gen_statem.start(__MODULE__, nil, [])
  end

  @impl :gen_statem
  def init(ctx) do
    rand_id = (:crypto.strong_rand_bytes(4) |> Base.encode16)
    {:ok, :starting, %__MODULE__{ctx: ctx, server_id: rand_id}, [{:next_event, :internal, :make_conf}]}
  end

  @impl true
  def handle_event(:internal, :make_conf, _, %{ctx: ctx} = data) do
    case DH.make_deploy_conf(ctx) do
      {:ok, conf} -> {:keep_state, %{data | conf: conf}, [{:next_event, :internal, :connect_ssh}]}
      {:error, _reason} = error -> {:next_state, :finished, %{data | result: error}, []}
    end
  end

  def handle_event(:internal, :connect_ssh, _, %{conf: conf, server_id: server_id} = data) do
    host = Map.get(conf, :host)
    user = Map.get(conf, :user)
    port = Map.get(conf, :port, 22)
    access_key = Map.get(conf, :ssh_key)

    case :ssh.start() do
      :ok ->
        key_path = Path.expand(access_key)
        priv_path = Path.join([Application.app_dir(:deployer), "priv", "#{server_id}", host])

        with(
          {_, :ok} <- {:make_priv_dir, File.mkdir_p(priv_path)},
          {_, priv_key_path} <- {:path_priv_key, Path.join(priv_path, "id_rsa")},
          {_, :ok} <- {:copy_ssh_key_to_priv, File.cp(keyp_path, priv_key_path)}
        ) do

          cl_host = String.to_charlist(host)
          cl_user = String.to_charlist(user)
          cl_priv_key_dir = String.to_charlist(priv_path)

          options = [user: cl_user, silently_accept_hosts: true, user_dir: cl_priv_key_dir]

          try do
            case :ssh.connect(cl_host, post, options) do
              {:ok, ref} ->
                {:next_state, :waiting, %{data | key_path: cl_priv_key_dir, host: cl_host, user: cl_user, ssh: ref}, []}
              {:error, _reason} = error->
                {:next_state, :finished, %{data | result: error}}
            end
          after
            File.rm(priv_key_path)
          end
        end

      {:error, _reason} = error -> {:next_state, :finished, %{data | result: error}}
    end
  end

  def handle_event({:call, from}, :get_state, state, %{result: result}) do
    {:keep_state_and_data, [{:reply, from, {state, result}}]}
  end

  def handle_event({:call, from}, {:action, action}, :waiting, data) do
    {:keep_state_and_data, [{:reply, from, {:action, action}}]}
  end
  
end
