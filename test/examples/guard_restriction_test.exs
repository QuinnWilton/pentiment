defmodule Pentiment.Examples.GuardRestrictionTest do
  use ExUnit.Case, async: true

  describe "GuardRestriction example" do
    test "module with allowed guards compiles successfully" do
      code = """
      defmodule TestAllowedGuards#{System.unique_integer([:positive])} do
        use Pentiment.Examples.GuardRestriction, ban: [:is_atom, :is_binary]

        def process(x) when is_integer(x), do: x * 2
        def process(x) when is_float(x), do: trunc(x) * 2
      end
      """

      assert [{module, _}] = Code.compile_string(code)
      assert module.process(5) == 10
      assert module.process(5.5) == 10
    end

    test "banned guard raises CompileError with Pentiment formatting" do
      code = """
      defmodule TestBannedGuard#{System.unique_integer([:positive])} do
        use Pentiment.Examples.GuardRestriction, ban: [:is_atom]

        def handle(x) when is_atom(x), do: Atom.to_string(x)
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(code)
        end

      # Verify the error contains Pentiment formatting.
      assert error.description =~ "Use of banned guard `is_atom/1`"
      assert error.description =~ "GUARD001"
      assert error.description =~ "banned guard"
      assert error.description =~ "this module bans guards: is_atom"
      assert error.description =~ "remove the `is_atom` guard"
    end

    test "multiple banned guards raises error for each" do
      code = """
      defmodule TestMultipleBanned#{System.unique_integer([:positive])} do
        use Pentiment.Examples.GuardRestriction, ban: [:is_atom, :is_binary]

        def handle_atom(x) when is_atom(x), do: :atom
        def handle_binary(x) when is_binary(x), do: :binary
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(code)
        end

      # Both violations should be reported.
      assert error.description =~ "is_atom"
      assert error.description =~ "is_binary"
    end

    test "functions without guards compile normally" do
      code = """
      defmodule TestNoGuards#{System.unique_integer([:positive])} do
        use Pentiment.Examples.GuardRestriction, ban: [:is_atom]

        def add(a, b), do: a + b
        def multiply(a, b), do: a * b
      end
      """

      assert [{module, _}] = Code.compile_string(code)
      assert module.add(2, 3) == 5
      assert module.multiply(2, 3) == 6
    end

    test "empty ban list allows all guards" do
      code = """
      defmodule TestEmptyBan#{System.unique_integer([:positive])} do
        use Pentiment.Examples.GuardRestriction, ban: []

        def is_it_atom?(x) when is_atom(x), do: true
        def is_it_atom?(_), do: false
      end
      """

      assert [{module, _}] = Code.compile_string(code)
      assert module.is_it_atom?(:foo) == true
      assert module.is_it_atom?("foo") == false
    end
  end
end
