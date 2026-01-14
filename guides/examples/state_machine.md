# State Machine DSL Example

This example demonstrates a DSL for defining state machines with multi-span
error messages that show related code locations.

## Use Case

You're building a state machine DSL and want to:

- Validate that transitions reference defined states
- Show both the error location and the similar state definition
- Provide helpful suggestions for typos

## Example Error Output

![State machine error](../images/state_machine.png)

## Usage

```elixir
defmodule TrafficLight do
  use Pentiment.Examples.StateMachine

  defstate :green
  defstate :yellow
  defstate :red

  deftransition :change, from: :green, to: :yellow
  deftransition :change, from: :yellow, to: :red
  deftransition :change, from: :red, to: :green
end

# Runtime API
TrafficLight.states()                    # [:green, :yellow, :red]
TrafficLight.can_transition?(:green, :change)  # true
TrafficLight.transition(:green, :change)       # {:ok, :yellow}
```

## Implementation

The full implementation is in `test/support/examples/state_machine.ex`.

### Key Points

**1. Track definitions with metadata**

```elixir
defmacro defstate(name) do
  caller = __CALLER__

  quote do
    @sm_states {
      unquote(name),
      %{
        file: unquote(caller.file),
        line: unquote(caller.line),
        column: 1
      }
    }
  end
end
```

**2. Validate in `__before_compile__`**

```elixir
defmacro __before_compile__(env) do
  states = Module.get_attribute(env.module, :sm_states) || []
  transitions = Module.get_attribute(env.module, :sm_transitions) || []
  state_names = Enum.map(states, fn {name, _meta} -> name end)

  errors =
    transitions
    |> Enum.flat_map(fn {_event, from, to, trans_meta} ->
      undefined_refs = []
      undefined_refs = if from not in state_names, do: [{:from, from, trans_meta} | undefined_refs], else: undefined_refs
      undefined_refs = if to not in state_names, do: [{:to, to, trans_meta} | undefined_refs], else: undefined_refs
      undefined_refs
    end)

  if errors != [] do
    reports = Enum.map(errors, fn error ->
      build_undefined_state_error(error, states, env.file)
    end)

    source = Pentiment.Elixir.source_from_env(env)
    formatted = Pentiment.format_all(reports, source, colors: false)
    raise CompileError, description: formatted
  end

  # ... generate runtime code
end
```

**3. Build multi-span errors**

```elixir
defp build_undefined_state_error(field, undefined_state, trans_meta, states, _file) do
  state_names = Enum.map(states, fn {name, _} -> name end)
  similar = find_similar(undefined_state, state_names)

  trans_span = Pentiment.Span.position(trans_meta.line, trans_meta.column)

  report =
    Pentiment.Report.error("Transition references undefined state `#{undefined_state}`")
    |> Pentiment.Report.with_code("SM001")
    |> Pentiment.Report.with_source(trans_meta.file)
    |> Pentiment.Report.with_label(Pentiment.Label.primary(trans_span, "undefined state"))

  report =
    if similar do
      {_name, similar_meta} = Enum.find(states, fn {n, _} -> n == similar end)
      def_span = Pentiment.Span.position(similar_meta.line, similar_meta.column)

      report
      |> Pentiment.Report.with_label(
        Pentiment.Label.secondary(def_span, "did you mean this state?", source: similar_meta.file)
      )
      |> Pentiment.Report.with_help("change `#{field}: :#{undefined_state}` to `#{field}: :#{similar}`")
    else
      report
    end

  Pentiment.Report.with_note(report, "defined states are: #{Enum.join(state_names, ", ")}")
end
```

## Key Techniques

- **Module attributes**: Accumulate definitions with `@sm_states`
- **`@before_compile`**: Defer validation until all definitions are collected
- **Multiple labels**: Use primary for the error, secondary for context
- **`source:` option**: Labels can reference different source files

## Testing

```elixir
test "undefined state raises CompileError with multi-span error" do
  code = """
  defmodule TestStateMachine do
    use Pentiment.Examples.StateMachine
    defstate :green
    deftransition :change, from: :green, to: :yello
  end
  """

  error = assert_raise CompileError, fn -> Code.compile_string(code) end
  assert error.description =~ "undefined state"
  assert error.description =~ "change `to: :yello` to `to: :yellow`"
end
```
