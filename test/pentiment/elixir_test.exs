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

    test "computes end column for variable nodes" do
      # Variable `foo` at column 5 should span columns 5-8 (3 chars)
      ast = {:foo, [line: 10, column: 5], nil}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 10,
               start_column: 5,
               end_line: 10,
               end_column: 8
             } = span
    end

    test "computes end column for function calls with closing metadata" do
      # is_atom(x) at columns 1-10 with closing paren at column 10
      ast =
        {:is_atom, [line: 1, column: 1, closing: [line: 1, column: 10]],
         [{:x, [line: 1, column: 9], nil}]}

      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 11
             } = span
    end

    test "handles multi-line function calls" do
      # Function call spanning multiple lines
      ast = {:foo, [line: 1, column: 1, closing: [line: 3, column: 1]], []}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 3,
               end_column: 2
             } = span
    end

    test "computes end for maps with closing metadata" do
      # %{a: 1} - map from column 1 to 7
      ast = {:%{}, [closing: [line: 1, column: 7], line: 1, column: 1], [a: 1]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 8
             } = span
    end

    test "computes end for anonymous functions" do
      # fn x -> x end - fn at column 1, end at column 11
      ast = {:fn, [closing: [line: 1, column: 11], line: 1, column: 1], [{:->, [], []}]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 12
             } = span
    end

    test "computes end for case expressions with end metadata" do
      # case x do ... end - case at column 1, end at column 1 of line 3
      ast = {:case, [do: [line: 1, column: 8], end: [line: 3, column: 1], line: 1, column: 1], []}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 3,
               end_column: 4
             } = span
    end

    test "computes end for single-segment aliases" do
      # Foo - alias at column 1, 3 chars
      ast = {:__aliases__, [line: 1, column: 1], [:Foo]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 4
             } = span
    end

    test "computes end for multi-segment aliases with last metadata" do
      # Foo.Bar.Baz - starts at column 1, last segment Baz at column 9
      ast = {:__aliases__, [last: [line: 1, column: 9], line: 1, column: 1], [:Foo, :Bar, :Baz]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 12
             } = span
    end

    test "computes end for binaries with closing metadata" do
      # <<1, 2>> - binary from column 1 to 7
      ast = {:<<>>, [closing: [line: 1, column: 7], line: 1, column: 1], [1, 2]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 8
             } = span
    end

    test "estimates end for function calls without closing metadata using name length" do
      # is_atom(x) without :closing - should span 7 chars for "is_atom"
      ast = {:is_atom, [line: 1, column: 22], [{:x, [line: 1, column: 30], nil}]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 22,
               end_line: 1,
               end_column: 29
             } = span
    end

    test "computes end for binary operators using operator length" do
      # x + y - operator at column 3, 1 char
      ast = {:+, [line: 1, column: 3], [{:x, [], nil}, {:y, [], nil}]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 3,
               end_line: 1,
               end_column: 4
             } = span

      # x |> y - operator at column 3, 2 chars
      ast = {:|>, [line: 1, column: 3], [{:x, [], nil}, {:y, [], nil}]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 3,
               end_line: 1,
               end_column: 5
             } = span
    end

    test "computes end for keyword operators using name length" do
      # not x - keyword at column 1, 3 chars
      ast = {:not, [line: 1, column: 1], [{:x, [], nil}]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 4
             } = span

      # x and y - keyword at column 3, 3 chars
      ast = {:and, [line: 1, column: 3], [{:x, [], nil}, {:y, [], nil}]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 3,
               end_line: 1,
               end_column: 6
             } = span
    end

    test "computes end for special forms using operator length" do
      # @foo - @ at column 1, 1 char
      ast = {:@, [line: 1, column: 1], [{:foo, [], nil}]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 2
             } = span

      # ^x - ^ at column 1, 1 char
      ast = {:^, [line: 1, column: 1], [{:x, [], nil}]}
      span = PentimentElixir.span_from_ast(ast)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 2
             } = span
    end
  end

  describe "span_for_value/3" do
    test "creates span for atom with correct length" do
      # :foo is 4 characters
      span = PentimentElixir.span_for_value(:foo, 10, 5)

      assert %Span.Position{
               start_line: 10,
               start_column: 5,
               end_line: 10,
               end_column: 9
             } = span
    end

    test "creates span for integer with correct length" do
      # 12345 is 5 characters
      span = PentimentElixir.span_for_value(12345, 1, 1)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 6
             } = span
    end

    test "creates span for string with correct length" do
      # "hi" is 4 characters (including quotes)
      span = PentimentElixir.span_for_value("hi", 5, 10)

      assert %Span.Position{
               start_line: 5,
               start_column: 10,
               end_line: 5,
               end_column: 14
             } = span
    end

    test "creates span for negative integer" do
      # -42 is 3 characters
      span = PentimentElixir.span_for_value(-42, 1, 1)

      assert %Span.Position{
               start_line: 1,
               start_column: 1,
               end_line: 1,
               end_column: 4
             } = span
    end
  end

  describe "value_display_length/1" do
    test "calculates atom length including colon" do
      assert 4 == PentimentElixir.value_display_length(:foo)
      assert 2 == PentimentElixir.value_display_length(:x)
      assert 12 == PentimentElixir.value_display_length(:hello_world)
    end

    test "calculates integer length" do
      assert 1 == PentimentElixir.value_display_length(0)
      assert 1 == PentimentElixir.value_display_length(9)
      assert 2 == PentimentElixir.value_display_length(10)
      assert 5 == PentimentElixir.value_display_length(12345)
      assert 3 == PentimentElixir.value_display_length(-42)
    end

    test "calculates string length including quotes" do
      assert 2 == PentimentElixir.value_display_length("")
      assert 7 == PentimentElixir.value_display_length("hello")
    end

    test "returns 1 for unknown types" do
      assert 1 == PentimentElixir.value_display_length([1, 2, 3])
      assert 1 == PentimentElixir.value_display_length(%{a: 1})
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
