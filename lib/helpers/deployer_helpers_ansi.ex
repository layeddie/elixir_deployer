defmodule Deployer.Helpers.ANSI do
  import IO.ANSI, only: [red: 0, red_background: 0, black: 0, default_background: 0, default_color: 0, green: 0, black_background: 0, yellow: 0, blink_slow: 0, blink_off: 0, magenta: 0, cursor_right: 1, cursor_left: 1]

  def error({:deployer_init?, false}) do
    IO.write(red() <> "Deployer hasn't been initialised yet. Please run " <> default_color() <> "mix deployer.init" <> red() <> " from the root folder of your app before attempting any other task." <> default_color() <> "\n")
  end
  def error(msg) when is_binary(msg) do
    IO.write(red() <> msg <> default_color() <> "\n")
  end

  def error(msg), do: error(inspect(msg))

  def success(msg) when is_binary(msg) do
    IO.write(green() <> msg <> default_color() <> "\n")
  end

  def success(msg), do: success(inspect(msg))
  
  def warn(msg) when is_binary(msg) do
    IO.write(yellow() <> msg <> default_color() <> "\n")
  end
  
  def warn(msg), do: warn(inspect(msg))

  def info(msg) when is_binary(msg) do
    IO.write(msg <> "\n")
  end

  def info(msg), do: info(inspect(msg))

  def wait_input(msg) do
    IO.write(msg <> " ")
    resp =
      IO.read(:line)
      |> String.trim_trailing()

    IO.write("\n")
    resp
  end

  def info_command(command, description) do
    IO.write(cursor_right(4) <> ">> " <> green() <> command <> yellow() <> "  :::: " <> description <> "\n" <> default_color())
  end

  def response(msg) do
    Enum.each(msg, fn(m) ->
      IO.write(magenta() <> m <> default_color() <> "\n")
    end)
  end
end
