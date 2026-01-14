# Config Validation Example

This example demonstrates compile-time configuration validation with typo detection
and helpful suggestions.

## Use Case

You're building a library that accepts configuration options, and you want to:

- Validate option keys at compile time
- Suggest corrections for typos
- Show which keys are valid

## Example Error Output

![Config validation error](images/config_validation.png)

## Usage

```elixir
defmodule MyApp.Config do
  use Pentiment.Examples.ConfigValidation

  config :database,
    host: "localhost",
    port: 5432,           # valid
    timeout: 30_000       # valid
end
```

## Implementation

The full implementation is in `test/support/examples/config_validation.ex`.

### Key Points

**1. Define valid keys**

```elixir
@valid_keys [:host, :port, :timeout, :pool_size, :database, :username, :password]
```

**2. Validate in the macro**

```elixir
defmacro config(name, opts) do
  caller = __CALLER__

  for {key, _value} <- opts do
    unless key in @valid_keys do
      span = extract_key_span(opts, key, caller)

      report =
        Pentiment.Report.error("Unknown configuration key `#{key}`")
        |> Pentiment.Report.with_code("CFG001")
        |> Pentiment.Report.with_source(caller.file)
        |> Pentiment.Report.with_label(Pentiment.Label.primary(span, "unknown key"))
        |> maybe_add_suggestion(key, @valid_keys)
        |> Pentiment.Report.with_note("valid keys are: #{Enum.join(@valid_keys, ", ")}")

      source = Pentiment.Elixir.source_from_env(caller)
      formatted = Pentiment.format(report, source, colors: false)
      raise CompileError, description: formatted
    end
  end

  quote do
    @configs {unquote(name), unquote(opts)}
  end
end
```

**3. Suggest similar keys using Jaro distance**

```elixir
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
```

## Key Techniques

- **`__CALLER__`**: Access the macro's call site for file and line information
- **`String.jaro_distance/2`**: Find similar strings for typo suggestions
- **`Pentiment.Elixir.source_from_env/1`**: Get source content from the environment
- **`colors: false`**: Disable ANSI colors for CompileError descriptions

## Testing

```elixir
test "invalid key raises CompileError with Pentiment formatting" do
  code = """
  defmodule TestConfig do
    use Pentiment.Examples.ConfigValidation
    config :database, prot: 5432
  end
  """

  error = assert_raise CompileError, fn -> Code.compile_string(code) end
  assert error.description =~ "Unknown configuration key `prot`"
  assert error.description =~ "did you mean `port`?"
end
```
