defmodule Mix.Tasks.Testing do
  use Mix.Task

  def run(args) do
    Mix.Shell.IO.info(inspect(Mix.Project.get()))
    Mix.Shell.IO.info(inspect(Mix.Project.config()))
  end

end
