defmodule Deployer.Release do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field            :id,         :string
    field            :path,       :string
    field            :name,       :string
    field            :tags,       {:array, :string}, default: []
    field            :metadata,   :map, default: %{}
    field            :created_at, :utc_datetime
  end
end
