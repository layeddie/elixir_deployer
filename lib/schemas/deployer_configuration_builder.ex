defmodule Deployer.Configuration.Builder do
  use Ecto.Schema

  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field :host,      :string
    field :user,      :string
    field :name,      :string
    field :path,      :string
    field :ssh_key,   :string
    field :tags,      {:array, :string}, default: []

    embeds_one :after_mf, Deployer.Configuration.MF
  end
end
