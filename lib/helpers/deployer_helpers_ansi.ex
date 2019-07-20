defmodule Deployer.Helpers.ANSI do
  import IO.ANSI, only: [red: 0, red_background: 0, black: 0, default_background: 0, default_color: 0, green: 0, black_background: 0, yellow: 0, blink_slow: 0, blink_off: 0, magenta: 0]

  defmacro error(msg) do
    quote do
      case unquote(msg) do
        {:deployer_init?, false} ->
          Mix.Shell.IO.info(red() <> "Deployer hasn't been initialised yet. Please run " <> default_color() <> "mix deployer.init" <> red() <> " from the root folder of your app before attempting any other task." <> default_color())
        msg ->
          Mix.Shell.IO.info(red() <> inspect(msg) <> default_color())
      end
    end
  end

  defmacro success(msg) do
    quote do
      Mix.Shell.IO.info(green() <> inspect(unquote(msg)) <> default_color())
    end
  end

  defmacro warn(msg) do
    quote do
      Mix.Shell.IO.info(yellow() <> inspect(unquote(msg)) <> default_color())
    end
  end

  defmacro wait_input(msg) do
    quote do
      Mix.Shell.IO.prompt(unquote(msg))
    end
  end

  defmacro response(msg) do
    quote do
      Enum.each(unquote(msg), fn(m) ->
          IO.puts(magenta() <> m <> default_color())
      end)
    end
  end
end
