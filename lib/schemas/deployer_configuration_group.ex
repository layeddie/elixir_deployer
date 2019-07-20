defmodule Deployer.Configuration.Group do
  use Ecto.Schema

  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field :targets, {:array, :string}
  end
end
