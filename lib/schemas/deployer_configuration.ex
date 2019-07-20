defmodule Deployer.Configuration do
  use Ecto.Schema
  
  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field :targets,  __MODULE__.TargetMap, default: %{}
    field :groups,   __MODULE__.GroupMap, default: %{}
    field :builders, __MODULE__.BuilderMap, default: %{}
  end
end
