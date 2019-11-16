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
    field            :unix_ts,    :integer
    field            :ref,        :string
  end

  @spec remove_latest(list(%Deployer.Release{}), String.t) :: list(%Deployer.Release{})
  def remove_latest(structs, name) do
    Enum.map(structs, fn
      (%{name: ^name, tags: tags} = struct) ->
        %{struct | tags: Enum.reject(tags, fn(tag) -> tag == "latest" end)}
      (struct) -> struct
    end)
  end
end
