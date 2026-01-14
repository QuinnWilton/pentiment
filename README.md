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

## Example Output

![State machine error example](images/state_machine.png)

## Usage

```elixir
alias Pentiment.{Report, Label, Span, Source}

# Create a diagnostic report
report =
  Report.error("Transition references undefined state `gren`")
  |> Report.with_code("SM001")
  |> Report.with_source("lib/traffic_light.ex")
  |> Report.with_label(Label.primary(Span.position(11, 38), "undefined state"))
  |> Report.with_label(Label.secondary(Span.position(5, 3), "did you mean this state?"))
  |> Report.with_help("change `to: :gren` to `to: :green`")
  |> Report.with_note("defined states are: green, yellow, red")

# Load the source file
source = Source.from_file("lib/traffic_light.ex")

# Format and display
IO.puts(Pentiment.format(report, source))
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/pentiment>.
