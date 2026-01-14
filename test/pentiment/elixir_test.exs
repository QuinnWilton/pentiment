defmodule Pentiment.ElixirTest do
  use ExUnit.Case, async: true

  alias Pentiment.Elixir, as: PentimentElixir
  alias Pentiment.Span

  describe "span_from_meta/1" do
    test "extracts from keyword list with all fields" do
      span = PentimentElixir.span_from_meta(line: 10, column: 5)

      assert %Span.Position{start_line: 10, start_column: 5} = span
    end

    test "extracts end position when provided" do
      span = PentimentElixir.span_from_meta(line: 10, column: 5, end_line: 10, end_column: 15)

      assert %Span.Position{
               start_line: 10,
               start_column: 5,
               end_line: 10,
               end_column: 15
             } = span
    end

    test "defaults column to 1 when missing" do
      span = PentimentElixir.span_from_meta(line: 10)

      assert %Span.Position{start_line: 10, start_column: 1} = span
    end

    test "handles extra metadata fields" do
      meta = [line: 10, column: 5, file: "test.ex", foo: :bar, baz: 123]
      span = PentimentElixir.span_from_meta(meta)

      assert %Span.Position{start_line: 10, start_column: 5} = span
    end

    test "returns nil when line is missing" do
      assert nil == PentimentElixir.span_from_meta(column: 5)
    end

    test "returns nil for empty meta" do
      assert nil == PentimentElixir.span_from_meta([])
    end
  end

  describe "span_from_ast/1" do
    test "extracts from raw Elixir AST tuple" do
      ast = {:foo, [line: 10, column: 5], []}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{start_line: 10, start_column: 5} = span
    end

    test "extracts from binary operator AST" do
      # Simulating what quote produces, but with column info
      ast =
        {:+, [line: 20, column: 3],
         [{:x, [line: 20, column: 1], nil}, {:y, [line: 20, column: 5], nil}]}

      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{start_line: 20, start_column: 3} = span
    end

    test "extracts from struct with meta field" do
      node = %{meta: [line: 15, column: 8], other: :data}
      span = PentimentElixir.span_from_ast(node)

      assert %Span.Position{start_line: 15, start_column: 8} = span
    end

    test "returns nil for non-AST values" do
      assert nil == PentimentElixir.span_from_ast("not ast")
      assert nil == PentimentElixir.span_from_ast(123)
      assert nil == PentimentElixir.span_from_ast(%{foo: :bar})
      assert nil == PentimentElixir.span_from_ast(:atom)
    end

    test "returns nil for AST with empty meta" do
      ast = {:foo, [], []}
      assert nil == PentimentElixir.span_from_ast(ast)
    end
  end

  describe "leftmost_span/2" do
    test "returns first node's span when both have spans" do
      node1 = {:x, [line: 10, column: 5], nil}
      node2 = {:y, [line: 20, column: 10], nil}

      span = PentimentElixir.leftmost_span(node1, node2)

      assert %Span.Position{start_line: 10, start_column: 5} = span
    end

    test "returns second node's span when first has none" do
      node1 = {:x, [], nil}
      node2 = {:y, [line: 20, column: 10], nil}

      span = PentimentElixir.leftmost_span(node1, node2)

      assert %Span.Position{start_line: 20, start_column: 10} = span
    end

    test "returns first node's span when second has none" do
      node1 = {:x, [line: 10, column: 5], nil}
      node2 = {:y, [], nil}

      span = PentimentElixir.leftmost_span(node1, node2)

      assert %Span.Position{start_line: 10, start_column: 5} = span
    end

    test "returns nil when both have no span" do
      node1 = {:x, [], nil}
      node2 = {:y, [], nil}

      assert nil == PentimentElixir.leftmost_span(node1, node2)
    end
  end

  describe "file_from_env/1" do
    test "extracts file from Macro.Env" do
      env = %Macro.Env{file: "lib/test.ex", line: 1}
      assert "lib/test.ex" == PentimentElixir.file_from_env(env)
    end

    test "returns nil for nil env" do
      assert nil == PentimentElixir.file_from_env(nil)
    end
  end

  describe "line_from_env/1" do
    test "extracts line from Macro.Env" do
      env = %Macro.Env{file: "test.ex", line: 42}
      assert 42 == PentimentElixir.line_from_env(env)
    end

    test "returns nil for zero or negative line" do
      assert nil == PentimentElixir.line_from_env(%Macro.Env{file: "test.ex", line: 0})
      assert nil == PentimentElixir.line_from_env(%Macro.Env{file: "test.ex", line: -1})
    end

    test "returns nil for nil env" do
      assert nil == PentimentElixir.line_from_env(nil)
    end
  end

  describe "span_from_env/1" do
    test "extracts span from Macro.Env" do
      env = %Macro.Env{file: "test.ex", line: 42}
      span = PentimentElixir.span_from_env(env)

      # Env only provides line, column defaults to 1
      assert %Span.Position{start_line: 42, start_column: 1} = span
    end

    test "returns nil for zero line" do
      assert nil == PentimentElixir.span_from_env(%Macro.Env{file: "test.ex", line: 0})
    end

    test "returns nil for nil env" do
      assert nil == PentimentElixir.span_from_env(nil)
    end
  end
end
