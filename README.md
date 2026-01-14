# Pentiment

Beautiful, informative compiler-style error messages for Elixir.

Pentiment provides rich diagnostic formatting with highlighted source spans,
helpful suggestions, and clear error context. It's designed for compile-time
macro errors, DSL validation, parser error reporting, and configuration file
validation.

## Installation

Add `pentiment` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pentiment, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
alias Pentiment.{Report, Label, Span, Source}

# Create a diagnostic
report =
  Report.error("Type mismatch")
  |> Report.with_code("E001")
  |> Report.with_source("lib/my_app.ex")
  |> Report.with_label(Label.primary(Span.position(15, 10), "expected `integer`, found `float`"))
  |> Report.with_help("use `trunc/1` to convert")

# Create a source
source = Source.from_string("lib/my_app.ex", """
defmodule MyApp do
  def add(x, y) do
    x + y
  end

  def run do
    add(1, 2)
  end

  def example do
    x = 10
    y = 20
    z = 30
    result = x + y + 1.5
    result + z
  end
end
""")

# Format and display
IO.puts(Pentiment.format(report, source))
```

Output:

```
error[E001]: Type mismatch
   ╭─[lib/my_app.ex:15:10]
   │
13 │     z = 30
14 │     result = x + y + 1.5
   •                      ─┬─
   •                       ╰── expected `integer`, found `float`
15 │     result + z
   │
   ╰─────
      help: use `trunc/1` to convert
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/pentiment>.
