# Examples Overview

Pentiment helps you create beautiful, informative error messages for your Elixir
macros and DSLs. This guide walks through five example integrations demonstrating
different patterns.

## Available Examples

| Example | Pattern | Dependencies |
|---------|---------|--------------|
| [Config Validation](config_validation.md) | Compile-time validation with typo detection | None |
| [State Machine DSL](state_machine.md) | Multi-span errors with related definitions | None |
| [Guard Restriction](guard_restriction.md) | AST walking with `__before_compile__` | None |
| [Parser Errors](parser_errors.md) | Rich error messages from parsers | nimble_parsec |
| [YAML Validation](yaml_validation.md) | Semantic validation of parsed files | yamerl |

## Quick Start

The simplest integration pattern is:

1. Extract span information from your AST or source
2. Build a `Pentiment.Report` with labels pointing to the problem
3. Format and raise the error

```elixir
defmacro my_macro(expr) do
  if invalid?(expr) do
    span = Pentiment.Elixir.span_from_ast(expr)
    source = Pentiment.Elixir.source_from_env(__CALLER__)

    report = Pentiment.Report.error("Invalid expression")
      |> Pentiment.Report.with_code("E001")
      |> Pentiment.Report.with_source(__CALLER__.file)
      |> Pentiment.Report.with_label(Pentiment.Label.primary(span, "problem here"))
      |> Pentiment.Report.with_help("try this instead")

    raise CompileError, description: Pentiment.format(report, source, colors: false)
  end

  # ... normal macro expansion
end
```

## Key Concepts

### Spans

Spans identify regions in source code. Use `Pentiment.Span.position/4` for
line/column ranges or `Pentiment.Elixir.span_from_ast/1` to extract from AST:

```elixir
# Manual span: line 10, columns 5-15
span = Pentiment.Span.position(10, 5, 10, 15)

# From Elixir AST
span = Pentiment.Elixir.span_from_ast(ast_node)

# From AST metadata
span = Pentiment.Elixir.span_from_meta([line: 10, column: 5])
```

### Labels

Labels annotate spans with messages. Use primary labels for the main error
location and secondary labels for related context:

```elixir
# Primary: the main problem
Pentiment.Label.primary(error_span, "expected integer")

# Secondary: supporting context
Pentiment.Label.secondary(definition_span, "declared here")
```

### Reports

Reports combine everything into a formatted diagnostic:

```elixir
Pentiment.Report.error("Type mismatch")
|> Pentiment.Report.with_code("E001")        # optional error code
|> Pentiment.Report.with_source(file_path)   # source file name
|> Pentiment.Report.with_label(label)        # add labels
|> Pentiment.Report.with_help("suggestion")  # add help text
|> Pentiment.Report.with_note("context")     # add notes
```

### Formatting

Format reports with `Pentiment.format/3`:

```elixir
# From file path
formatted = Pentiment.format(report, "lib/app.ex")

# From Source struct
source = Pentiment.Source.from_file("lib/app.ex")
formatted = Pentiment.format(report, source)

# From string content
source = Pentiment.Source.from_string("input.txt", content)
formatted = Pentiment.format(report, source, colors: false)
```

## Example Output

![State machine error example](https://raw.githubusercontent.com/QuinnWilton/pentiment/main/images/state_machine.png)

## Running the Examples

The examples are available in `test/support/examples/` and tested in
`test/examples/`. To run the example tests:

```bash
mix test test/examples/
```

Examples requiring optional dependencies (nimble_parsec, yamerl) are
automatically skipped if the dependencies aren't available.
