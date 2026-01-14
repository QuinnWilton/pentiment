# Parser Errors Example

This example demonstrates rich error messages from NimbleParsec parsers.

> **Requires:** `{:nimble_parsec, "~> 1.0"}` as a test dependency

## Use Case

You're building a parser and want to:

- Convert parse failures into helpful error messages
- Show the exact position where parsing failed
- Provide contextual hints about what went wrong

## Example Error Output

![Parser error](images/parser_errors.png)

## Usage

```elixir
case Pentiment.Examples.ParserErrors.parse("expr.lang", "let x = 10") do
  {:ok, ast} ->
    evaluate(ast)

  {:error, formatted} ->
    IO.puts(formatted)
end
```

## Implementation

The full implementation is in `test/support/examples/parser_errors.ex`.

### Key Points

**1. Define the parser with NimbleParsec**

```elixir
defmodule Pentiment.Examples.ParserErrors do
  import NimbleParsec

  identifier =
    ascii_char([?a..?z, ?_])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:ident)

  integer_literal =
    optional(ascii_char([?-]))
    |> ascii_string([?0..?9], min: 1)
    |> reduce({__MODULE__, :parse_integer, []})
    |> unwrap_and_tag(:int)

  # ... more grammar definitions

  defparsec(:parse_let, let_binding)
end
```

**2. Convert parse positions to spans**

NimbleParsec returns position information in its results:

```elixir
case parse_let(input) do
  {:ok, tokens, "", _, _, _} ->
    {:ok, tokens}

  {:ok, _tokens, rest, _, {line, line_offset}, byte_offset} ->
    # Partial parse - unexpected content remains
    col = byte_offset - line_offset + 1
    span = Pentiment.Span.position(line, col, line, col + String.length(unexpected))
    # ... build error

  {:error, message, _rest, _, {line, line_offset}, byte_offset} ->
    col = byte_offset - line_offset + 1
    span = Pentiment.Span.position(line, col)
    # ... build error
end
```

**3. Analyze unexpected input for context**

```elixir
defp analyze_unexpected(rest) do
  trimmed = String.trim_leading(rest)

  case trimmed do
    "+" <> _ -> {"+", "operator requires a right-hand operand"}
    "-" <> _ -> {"-", "operator requires a right-hand operand"}
    "*" <> _ -> {"*", "operator requires a right-hand operand"}
    "/" <> _ -> {"/", "operator requires a right-hand operand"}
    ")" <> _ -> {")", "unmatched closing parenthesis"}
    <<c, _::binary>> -> {<<c>>, nil}
    "" -> {"end of input", "expression is incomplete"}
  end
end
```

**4. Build the error report**

```elixir
def parse(source_name, input) do
  source = Pentiment.Source.from_string(source_name, input)

  case parse_let(input) do
    {:ok, tokens, "", _, _, _} ->
      {:ok, tokens}

    {:ok, _tokens, rest, _, {line, line_offset}, byte_offset} ->
      col = byte_offset - line_offset + 1
      {unexpected, hint} = analyze_unexpected(rest)
      span = Pentiment.Span.position(line, col, line, col + String.length(unexpected))

      report =
        Pentiment.Report.error("Unexpected token")
        |> Pentiment.Report.with_code("PARSE001")
        |> Pentiment.Report.with_source(source_name)
        |> Pentiment.Report.with_label(
          Pentiment.Label.primary(span, "unexpected `#{unexpected}`")
        )
        |> maybe_add_note(hint)

      {:error, Pentiment.format(report, source, colors: false)}
  end
end
```

## Key Techniques

- **NimbleParsec position tuple**: `{line, line_offset}` and `byte_offset`
- **Column calculation**: `col = byte_offset - line_offset + 1`
- **`Pentiment.Source.from_string/2`**: Create source from in-memory content
- **Contextual hints**: Analyze remaining input to provide helpful messages

## Testing

```elixir
test "valid input parses successfully" do
  assert {:ok, [let_binding: [:let, {:ident, "x"}, :equals, {:expr, [int: 10]}]]} =
    Pentiment.Examples.ParserErrors.parse("test.expr", "let x = 10")
end

test "unexpected token produces Pentiment error" do
  {:error, formatted} = Pentiment.Examples.ParserErrors.parse("test.expr", "let x = 10 extra")

  assert formatted =~ "Unexpected token"
  assert formatted =~ "PARSE001"
  assert formatted =~ "unexpected `e`"
end
```
