defmodule Pentiment.Examples.ParserErrorsTest do
  use ExUnit.Case, async: true
  alias Pentiment.Examples.ParserErrors

  @moduletag :requires_nimble_parsec

  describe "ParserErrors example" do
    test "valid input parses successfully" do
      assert {:ok, [let_binding: [:let, {:ident, "x"}, :equals, {:expr, [int: 10]}]]} =
               ParserErrors.parse("test.expr", "let x = 10")
    end

    test "valid input with operators parses successfully" do
      assert {:ok, _} = ParserErrors.parse("test.expr", "let x = 10 + 5")
      assert {:ok, _} = ParserErrors.parse("test.expr", "let x = 10 * 5 + 2")
    end

    test "unexpected token produces Pentiment error" do
      # Extra content after the expression is flagged as unexpected.
      {:error, formatted} = ParserErrors.parse("test.expr", "let x = 10 extra")

      assert formatted =~ "Unexpected token"
      assert formatted =~ "PARSE001"
      # Should show the unexpected character.
      assert formatted =~ "unexpected `e`"
    end

    test "error shows source context" do
      {:error, formatted} = ParserErrors.parse("test.expr", "let x = abc def")

      # Should show the source line.
      assert formatted =~ "let x = abc def"
    end

    test "simple valid expressions parse" do
      assert {:ok, _} = ParserErrors.parse("t", "let foo = 42")
      assert {:ok, _} = ParserErrors.parse("t", "let bar = x")
    end
  end
end
