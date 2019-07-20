defmodule Deployer.Release.Context do

  import Ecto.Changeset, only: [cast: 3, apply_action: 2, validate_required: 2]

  @allowed_fields Deployer.Release.__schema__(:fields) -- [:id]
  @required_fields @allowed_fields -- [:tags, :metadata, :id]  
  
  def create(params, struct \\ %Deployer.Release{}) do
    struct
    |> cast(params, @allowed_fields)
    |> validate_required(@required_fields)
    |> apply_action(:insert)
    |> case do
         {:ok, rel} -> rel
         {:error, errors} -> {:error_creating_release_struct, errors}
       end
  end
end
