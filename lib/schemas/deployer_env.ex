defmodule Deployer.Env do
  use Ecto.Schema

  @derive Jason.Encoder
  @primary_key false

  embedded_schema do
    field :env,       :map, default: %{}
    field :datetime,  :utc_datetime
    field :unix_ts,   :integer
    
    embeds_one :paths,  Deployer.Env.Paths
    embeds_one :config, Deployer.Configuration
  end
end

