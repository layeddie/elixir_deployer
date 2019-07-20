defmodule Deployer.Helpers.DETS do
  alias Deployer.Helpers, as: DH
  
  @dets_name :deployer_dets

  @default_init [
    {:available_releases, []},
    {:counter, 0}
  ]

  def dets_name, do: @dets_name

  def path(config_path) do
    Path.join(config_path, Atom.to_string(@dets_name))
  end

  def create_dets_entries do
    case open_dets_table() do
      :ok -> :dets.insert(@dets_name, @default_init)
      error -> error
    end
  end

  def close do
    :dets.close(@dets_name)
  end

  def open_dets_table(with_name \\ false) do
    path = DH.read_env(:deployer_dets_path)
    case !path do
      true -> {:error, ":dets_path is not set"}
      _ ->
        case :dets.open_file(@dets_name, [{:file, path}]) do
          {:ok, _} -> if(with_name, do: {:ok, @dets_name}, else: :ok)
          error -> error
        end
    end
  end

  def check_release_exists(release, releases) do
    Enum.any?(releases, fn(%{id: id}) ->
      case (
        case is_binary(release) do
          true ->
            case Integer.parse(release) do
              {int, _} -> int
              _ -> nil
            end
          _ when is_integer(release) -> release
          _ -> nil
        end
      ) do
        n_release when is_integer(n_release) -> n_release == id
        _ -> false
      end
    end)
  end

  def get_existing_releases do
    case open_dets_table() do
      :ok ->
        case :dets.lookup(@dets_name, :available_releases) do
          [{_, releases}] ->
            n_releases = maybe_clean_up_releases(releases)
            :dets.insert(@dets_name, {:available_releases, n_releases})
            close()
            {:ok, n_releases}
        end
      error ->
        {:error, :opening_dets, error}
    end
  end

  def maybe_clean_up_releases(releases) do
    Enum.reject(releases, fn(%{path: path}) ->
      !(File.exists?(path))
    end)
  end

  def get_and_update_counter(is_open \\ false) do
    case is_open || open_dets_table() do
      is when is in [true, :ok]  ->
        {:ok, :dets.update_counter(@dets_name, :counter, 1)}
      _ ->
        :error
    end
  end
end
