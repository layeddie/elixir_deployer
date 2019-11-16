defmodule Deployer.Configuration.Context do
  import Ecto.Changeset, only: [cast: 3, apply_action: 2, cast_embed: 3]

  alias Deployer.Configuration
  alias Configuration.{Target, Builder, Group, MF}

  def create_config(config) do
    %Configuration{}
    |> configuration_changeset(config)
    |> apply_action(:insert)
  end

  def configuration_changeset(struct, params) do
    struct
    |> cast(params, Configuration.__schema__(:fields))
  end

  def create_target(target) do
    %Target{}
    |> target_changeset(target)
    |> apply_action(:insert)
  end

  def target_changeset(struct, params) do
    struct
    |> cast(params, Target.__schema__(:fields) -- [:after_mf])
    |> cast_embed(:after_mf, with: &mf_changeset/2)
  end

  def create_group(group) do
    %Group{}
    |> group_changeset(group)
    |> apply_action(:insert)
  end
  
  def group_changeset(struct, params) do
    struct
    |> cast(params, Group.__schema__(:fields))
  end

  def mf_changeset(struct, params) do
    struct
    |> cast(params, MF.__schema__(:fields))
  end

  def validate_target(
    %Target{
      host: host,
      user: user,
      name: name,
      path: path,
      ssh_key: ssh_key,
      after_mf: after_mf
    } = target
  ) do
    case (
      {
        is_binary(host) and
        is_binary(user) and
        is_binary(name) and
        is_binary(path) and
        is_binary(ssh_key),
        after_mf
      }
    ) do
      {true, %MF{}} -> {:ok, target}
      {true, nil} -> {:ok, target}
      _ -> {:error, {:invalid_configuration, target}}
    end
  end
end
