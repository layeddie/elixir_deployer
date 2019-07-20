defmodule Deployer.Configuration.MF do
  use Ecto.Schema

  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field :mod,  Deployer.SafeAtom
    field :fun,  Deployer.SafeAtom
  end
end
