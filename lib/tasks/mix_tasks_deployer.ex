defmodule Mix.Tasks.Deployer do
  use Mix.Task

  def run([task | args]) do
    Application.load(:deployer)
    Mix.Task.run("deployer.#{task}", args)
  end
end
