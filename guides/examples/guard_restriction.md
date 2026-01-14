# Guard Restriction Example

This example demonstrates compile-time validation of guard usage by walking
the AST with `Macro.prewalk/3` and using `__before_compile__`.

## Use Case

You're building a library that restricts certain guards and want to:

- Ban specific guards in a module
- Walk the AST to find violations
- Provide clear error messages with alternatives

## Example Error Output

![Guard restriction error](images/guard_restriction.png)

## Usage

```elixir
defmodule MyApp.StrictModule do
  use Pentiment.Examples.GuardRestriction, ban: [:is_atom, :is_binary]

  # This will compile fine
  def process(x) when is_integer(x), do: x * 2

  # This will fail: is_atom is banned
  def handle(x) when is_atom(x), do: Atom.to_string(x)
end
```

## Implementation

The full implementation is in `test/support/examples/guard_restriction.ex`.

### Key Points

**1. Override `def` to capture AST**

```elixir
defmacro __using__(opts) do
  banned = Keyword.get(opts, :ban, [])

  quote do
    @banned_guards unquote(banned)
    @before_compile Pentiment.Examples.GuardRestriction
    Module.register_attribute(__MODULE__, :guard_function_defs, accumulate: true)

    import Kernel, except: [def: 2]
    import Pentiment.Examples.GuardRestriction, only: [def: 2]
  end
end

defmacro def(call, do: body) do
  caller = __CALLER__

  quote do
    @guard_function_defs {
      unquote(Macro.escape(call)),
      unquote(Macro.escape(body)),
      unquote(caller.file),
      unquote(caller.line)
    }

    Kernel.def(unquote(call), do: unquote(body))
  end
end
```

**2. Walk guards with `Macro.prewalk/3`**

```elixir
defp find_banned_guard_calls(nil, _banned), do: []

defp find_banned_guard_calls(ast, banned_guards) do
  {_, violations} =
    Macro.prewalk(ast, [], fn
      {guard_name, meta, args} = node, acc when is_atom(guard_name) and is_list(args) ->
        if guard_name in banned_guards do
          {node, [{guard_name, meta} | acc]}
        else
          {node, acc}
        end

      node, acc ->
        {node, acc}
    end)

  Enum.reverse(violations)
end
```

**3. Extract function info including guards**

```elixir
defp extract_function_info({:when, _, [call, guards]}) do
  {name, args} = extract_name_and_args(call)
  {name, length(args), guards}
end

defp extract_function_info(call) do
  {name, args} = extract_name_and_args(call)
  {name, length(args), nil}
end
```

**4. Build violation errors**

```elixir
defp build_guard_violation_error(guard_name, guard_meta, banned_guards, file) do
  span =
    if guard_meta != [] do
      Pentiment.Elixir.span_from_meta(guard_meta)
    else
      Pentiment.Span.position(1, 1)
    end

  Pentiment.Report.error("Use of banned guard `#{guard_name}/1`")
  |> Pentiment.Report.with_code("GUARD001")
  |> Pentiment.Report.with_source(file)
  |> Pentiment.Report.with_label(Pentiment.Label.primary(span, "banned guard"))
  |> Pentiment.Report.with_note("this module bans guards: #{Enum.join(banned_guards, ", ")}")
  |> Pentiment.Report.with_help("remove the `#{guard_name}` guard")
end
```

## Key Techniques

- **Override `def`**: Capture function definitions with their AST
- **`Macro.escape/1`**: Store quoted expressions in module attributes
- **`Macro.prewalk/3`**: Walk the AST to find specific patterns
- **Guard clause AST**: Functions with guards use `{:when, meta, [call, guards]}`

## Testing

```elixir
test "banned guard raises CompileError" do
  code = """
  defmodule TestModule do
    use Pentiment.Examples.GuardRestriction, ban: [:is_atom]
    def handle(x) when is_atom(x), do: x
  end
  """

  error = assert_raise CompileError, fn -> Code.compile_string(code) end
  assert error.description =~ "Use of banned guard `is_atom/1`"
  assert error.description =~ "banned guard"
end

test "allowed guards compile normally" do
  code = """
  defmodule TestModule do
    use Pentiment.Examples.GuardRestriction, ban: [:is_atom]
    def process(x) when is_integer(x), do: x * 2
  end
  """

  assert [{module, _}] = Code.compile_string(code)
  assert module.process(5) == 10
end
```
