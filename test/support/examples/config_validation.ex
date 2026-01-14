defmodule Pentiment.Examples.ConfigValidation do
  @moduledoc """
  Example: Compile-time configuration validation with typo detection.

  This example demonstrates how to use Pentiment to provide rich error messages
  when validating configuration options in a macro. Key patterns shown:

  - Using search spans to find keyword keys in multi-line lists
  - Using `String.jaro_distance/2` for typo suggestions
  - Building reports with help and notes

  ## Usage

      defmodule MyApp.Config do
        use Pentiment.Examples.ConfigValidation

        config :database,
          host: "localhost",
          port: 5432,
          timeout: 30_000
      end

  ## Error Output

  If you use an invalid key:

      config :database,
        hoost: "localhost",
        port: 5432

  You'll get:

      error[CFG001]: Unknown configuration key `hoost`
         ╭─[lib/my_app/config.ex:4:5]
         │
       4 │     hoost: "localhost",
         •     ──┬──
         •       ╰── unknown key
         │
         ╰─────
            note: valid keys are: host, port, timeout, pool_size, database, username, password
            help: did you mean `host`?
  """

  @valid_keys [:host, :port, :timeout, :pool_size, :database, :username, :password]

  defmacro __using__(_opts) do
    quote do
      import Pentiment.Examples.ConfigValidation, only: [config: 2]
      Module.register_attribute(__MODULE__, :configs, accumulate: true)
    end
  end

  @doc """
  Defines a configuration section with validated keys.

  Validates all keys at compile time and raises a `CompileError` with
  a Pentiment-formatted error message if any key is unknown.
  """
  defmacro config(name, opts) do
    caller = __CALLER__

    # Validate each option key at compile time.
    for {key, _value} <- opts do
      unless key in @valid_keys do
        # Get the span for this key-value pair.
        # In a real implementation, we'd extract the exact position.
        # Here we use the macro's caller info as a fallback.
        span = extract_key_span(opts, key, caller)

        report =
          Pentiment.Report.error("Unknown configuration key `#{key}`")
          |> Pentiment.Report.with_code("CFG001")
          |> Pentiment.Report.with_source(caller.file)
          |> Pentiment.Report.with_label(Pentiment.Label.primary(span, "unknown key"))
          |> maybe_add_suggestion(key, @valid_keys)
          |> Pentiment.Report.with_note("valid keys are: #{Enum.join(@valid_keys, ", ")}")

        source = Pentiment.Elixir.source_from_env(caller)
        formatted = Pentiment.format(report, source)
        raise CompileError, description: formatted
      end
    end

    # Generate runtime code to store the config.
    quote do
      @configs {unquote(name), unquote(opts)}
    end
  end

  # Extracts the span for a specific key in a keyword list.
  # Uses a search span that resolves at format time, avoiding the need
  # to read files in the macro.
  defp extract_key_span(_opts, key, caller) do
    key_str = Atom.to_string(key)

    # Create a search span that finds "key:" starting from the caller's line.
    # The after_column ensures we search after the macro call site on the first line.
    # max_lines allows the key to be on a subsequent line (for multi-line keyword lists).
    # Note: Macro.Env may not have :column in all Elixir versions.
    after_col = Map.get(caller, :column, 1) || 1

    Pentiment.Span.search(
      line: caller.line,
      pattern: key_str,
      after_column: after_col,
      max_lines: 10
    )
  end

  defp maybe_add_suggestion(report, key, valid_keys) do
    key_str = to_string(key)

    similar =
      valid_keys
      |> Enum.map(fn valid -> {valid, String.jaro_distance(key_str, to_string(valid))} end)
      |> Enum.filter(fn {_, score} -> score > 0.7 end)
      |> Enum.max_by(fn {_, score} -> score end, fn -> nil end)

    case similar do
      {match, _} -> Pentiment.Report.with_help(report, "did you mean `#{match}`?")
      nil -> report
    end
  end
end
