defmodule Pentiment.Examples.GuardRestriction do
  @moduledoc """
  Example: Compile-time guard restriction with AST walking.

  This example demonstrates how to use Pentiment with `__before_compile__` to
  validate code patterns across an entire module. Key patterns shown:

  - Capturing function definitions with their AST
  - Walking AST with `Macro.prewalk/3` to find patterns
  - Building errors from multiple violations

  ## Usage

      defmodule MyApp.StrictModule do
        use Pentiment.Examples.GuardRestriction, ban: [:is_atom, :is_binary]

        # This will compile fine
        def process(x) when is_integer(x), do: x * 2

        # This will fail: is_atom is banned
        def handle(x) when is_atom(x), do: Atom.to_string(x)
      end

  ## Error Output

      error[GUARD001]: Use of banned guard `is_atom/1`
         ╭─[lib/my_app/strict_module.ex:8:20]
         │
       8 │   def handle(x) when is_atom(x), do: Atom.to_string(x)
         •                      ───┬───
         •                         ╰── banned guard
         │
         ╰─
            note: this module bans guards: is_atom, is_binary
            help: remove the `is_atom` guard
  """

  defmacro __using__(opts) do
    banned = Keyword.get(opts, :ban, [])

    quote do
      @banned_guards unquote(banned)
      @before_compile Pentiment.Examples.GuardRestriction
      Module.register_attribute(__MODULE__, :guard_function_defs, accumulate: true)

      # Import our custom def that captures metadata.
      import Kernel, except: [def: 2]
      import Pentiment.Examples.GuardRestriction, only: [def: 2]
    end
  end

  @doc """
  Custom `def` that captures function AST for later validation.
  """
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

  defmacro __before_compile__(env) do
    banned_guards = Module.get_attribute(env.module, :banned_guards) || []
    function_defs = Module.get_attribute(env.module, :guard_function_defs) || []

    violations = find_guard_violations(function_defs, banned_guards)

    if violations != [] do
      reports =
        Enum.map(violations, fn {guard_name, guard_ast, _func_name, _func_arity, file} ->
          build_guard_violation_error(guard_name, guard_ast, banned_guards, file)
        end)

      source = Pentiment.Elixir.source_from_env(env)
      formatted = Pentiment.format_all(reports, source, colors: false)

      raise CompileError, description: formatted
    end

    quote do: nil
  end

  defp find_guard_violations(function_defs, banned_guards) do
    Enum.flat_map(function_defs, fn {call, _body, file, _line} ->
      {func_name, func_arity, guards} = extract_function_info(call)

      guards
      |> find_banned_guard_calls(banned_guards)
      |> Enum.map(fn {guard_name, guard_ast} ->
        {guard_name, guard_ast, func_name, func_arity, file}
      end)
    end)
  end

  defp extract_function_info({:when, _, [call, guards]}) do
    {name, args} = extract_name_and_args(call)
    {name, length(args), guards}
  end

  defp extract_function_info(call) do
    {name, args} = extract_name_and_args(call)
    {name, length(args), nil}
  end

  defp extract_name_and_args({name, _, args}) when is_atom(name) and is_list(args) do
    {name, args}
  end

  defp extract_name_and_args({name, _, _}) when is_atom(name) do
    {name, []}
  end

  # Walk the guard AST to find calls to banned guards.
  defp find_banned_guard_calls(nil, _banned), do: []

  defp find_banned_guard_calls(ast, banned_guards) do
    {_, violations} =
      Macro.prewalk(ast, [], fn
        # Match guard calls like is_atom(x).
        {guard_name, _meta, args} = node, acc when is_atom(guard_name) and is_list(args) ->
          if guard_name in banned_guards do
            # Store the full AST node for span extraction.
            {node, [{guard_name, node} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(violations)
  end

  defp build_guard_violation_error(guard_name, guard_ast, banned_guards, file) do
    # span_from_ast computes end column from the function name length.
    span = Pentiment.Elixir.span_from_ast(guard_ast) || Pentiment.Span.position(1, 1)

    Pentiment.Report.error("Use of banned guard `#{guard_name}/1`")
    |> Pentiment.Report.with_code("GUARD001")
    |> Pentiment.Report.with_source(file)
    |> Pentiment.Report.with_label(Pentiment.Label.primary(span, "banned guard"))
    |> Pentiment.Report.with_note("this module bans guards: #{Enum.join(banned_guards, ", ")}")
    |> Pentiment.Report.with_help("remove the `#{guard_name}` guard")
  end
end
