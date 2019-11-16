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

  def create_dets_entries(ctx) do
    case open_dets_table(ctx) do
      {:ok, table} ->
        case :dets.insert(table, @default_init) do
          :ok ->
            :dets.close(table)
            :ok
          error ->
            {:error_creating_dets_initial, error}
        end
      error -> {:error_opening_dets, error}
    end
  end

  def close do
    :dets.close(@dets_name)
  end

  def open_dets_table(
    %Deployer.Env{
      paths: %Deployer.Env.Paths{
        dets_path_charlist: path
      }
    }
  ) do
    case !path do
      true -> {:error, ":dets_path is not set"}
      _ -> :dets.open_file(@dets_name, [{:file, path}])
    end
  end

  def get_if_release_exists(release, releases) do
    Enum.reduce_while(releases, false, fn(%{id: id, name: name, tags: tags} = rel, _) ->
      case is_binary(release) do
        true ->
          case Integer.parse(release) do
            {int, ""} ->
              case id == int do
                true -> {:halt, rel}
                _ -> {:cont, false}
              end
            _ ->
              case name == release and "latest" in tags do
                true -> {:halt, {:by_latest, rel}}
                _ -> {:cont, false}
              end
          end
        _ when release == id -> {:halt, rel}
      end
    end)
  end

  def get_existing_releases(ctx) do
    case open_dets_table(ctx) do
      {:ok, table} ->
        case :dets.lookup(table, :available_releases) do
          [{_, releases}] ->
            n_releases = maybe_clean_up_releases(releases)
            case :dets.insert(table, {:available_releases, n_releases}) do
              :ok ->
                :dets.close(table)
                {:ok, n_releases}
              error ->
                {:error_dets_get_existing_releases, error}
            end
        end
      error -> {:error_opening_dets, error}
    end
  end

  def write_releases(releases, ctx) do
    case open_dets_table(ctx) do
      {:ok, table} ->
        case :dets.insert(table, {:available_releases, releases}) do
          :ok ->
            :dets.close(table)
            {:ok, releases}
          error ->
            {:error, :writing_to_dets, releases}
        end
      error -> {:error_opening_dets, error}
    end
  end

  def add_release(%Deployer.Release{tags: tags, name: name} = release, ctx) do
    case open_dets_table(ctx) do
      {:ok, table} ->
        existing =
          case :dets.lookup(table, :available_releases) do
            [{_, existing}] -> existing
            _ -> []
          end

        case get_and_update_counter(ctx) do
          {:ok, id} ->
            IO.inspect({id, existing, release}, label: "existing")
            new_result = %{release | id: id, tags: ["latest" | tags]}
            latest_removed = Deployer.Release.remove_latest(existing, name)
            IO.inspect(new_result, label: "new_result")
            
            case :dets.insert(table, {:available_releases, [new_result | latest_removed]}) do
              :ok -> :dets.close(table)
              error -> error
            end
          error ->
            :dets.close(table)
            {:error_updating_dets_count, error}
        end
      error -> {:error_opening_dets, error}
    end
  end

  def maybe_clean_up_releases(releases) do
    Enum.reject(releases, fn(%{path: path}) ->
      !(File.exists?(path))
    end)
  end

  def get_and_update_counter(ctx) do
    case open_dets_table(ctx) do
      {:ok, table}  ->
        updated_counter = :dets.update_counter(table, :counter, 1)
        {:ok, updated_counter}
      error -> error
    end
  end
end
