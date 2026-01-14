defmodule Pentiment.Examples.ConfigValidationTest do
  use ExUnit.Case, async: true

  describe "ConfigValidation example" do
    test "valid config compiles successfully" do
      code = """
      defmodule TestValidConfig#{System.unique_integer([:positive])} do
        use Pentiment.Examples.ConfigValidation

        config :database,
          host: "localhost",
          port: 5432,
          timeout: 30_000
      end
      """

      assert [{module, _}] = Code.compile_string(code)
      assert module
    end

    test "invalid key raises CompileError with Pentiment formatting" do
      code = """
      defmodule TestInvalidConfig#{System.unique_integer([:positive])} do
        use Pentiment.Examples.ConfigValidation

        config :database,
          host: "localhost",
          prot: 5432
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(code)
        end

      # Verify the error contains Pentiment formatting.
      assert error.description =~ "Unknown configuration key `prot`"
      assert error.description =~ "CFG001"
      assert error.description =~ "did you mean `port`?"
      assert error.description =~ "valid keys are:"
    end

    test "suggestion works for similar keys" do
      code = """
      defmodule TestSuggestion#{System.unique_integer([:positive])} do
        use Pentiment.Examples.ConfigValidation

        config :database,
          hostt: "localhost"
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(code)
        end

      # Should suggest "host" for "hostt".
      assert error.description =~ "did you mean `host`?"
    end

    test "no suggestion for very different keys" do
      code = """
      defmodule TestNoSuggestion#{System.unique_integer([:positive])} do
        use Pentiment.Examples.ConfigValidation

        config :database,
          xyz_unknown: "value"
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(code)
        end

      # Should still show valid keys but maybe no suggestion.
      assert error.description =~ "Unknown configuration key `xyz_unknown`"
      assert error.description =~ "valid keys are:"
    end
  end
end
