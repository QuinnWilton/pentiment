defmodule Pentiment.SpanTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Pentiment.{Source, Span}
  alias Pentiment.Span.{Byte, Position, Search}

  describe "Span.Byte" do
    test "creates byte span with new/2" do
      span = Byte.new(42, 10)

      assert %Byte{start: 42, length: 10} = span
    end

    test "accepts start of 0" do
      span = Byte.new(0, 1)

      assert %Byte{start: 0, length: 1} = span
    end

    test "requires length >= 1" do
      assert_raise FunctionClauseError, fn ->
        Byte.new(0, 0)
      end
    end

    test "requires start >= 0" do
      assert_raise FunctionClauseError, fn ->
        Byte.new(-1, 10)
      end
    end

    test "requires integer arguments" do
      assert_raise FunctionClauseError, fn ->
        Byte.new(1.5, 10)
      end
    end
  end

  describe "Span.Position" do
    test "creates position span with full range" do
      span = Position.new(5, 10, 5, 20)

      assert %Position{
               start_line: 5,
               start_column: 10,
               end_line: 5,
               end_column: 20
             } = span
    end

    test "creates point span with just line and column" do
      span = Position.new(5, 10)

      assert %Position{
               start_line: 5,
               start_column: 10,
               end_line: nil,
               end_column: nil
             } = span
    end

    test "defaults column to 1" do
      span = Position.new(5)

      assert %Position{start_line: 5, start_column: 1} = span
    end

    test "requires start_line >= 1" do
      assert_raise FunctionClauseError, fn ->
        Position.new(0, 1)
      end
    end

    test "requires start_column >= 1" do
      assert_raise FunctionClauseError, fn ->
        Position.new(1, 0)
      end
    end

    test "allows multi-line spans" do
      span = Position.new(5, 1, 10, 20)

      assert %Position{start_line: 5, end_line: 10} = span
    end
  end

  describe "Position.point?/1" do
    test "returns true for point spans" do
      span = Position.new(5, 10)

      assert Position.point?(span)
    end

    test "returns false for range spans" do
      span = Position.new(5, 10, 5, 20)

      refute Position.point?(span)
    end

    test "returns false when only end_line is set" do
      span = %Position{start_line: 5, start_column: 10, end_line: 5, end_column: nil}

      refute Position.point?(span)
    end
  end

  describe "Position.single_line_range/1" do
    test "returns line and columns for single-line range" do
      span = Position.new(5, 10, 5, 20)

      assert {5, 10, 20} = Position.single_line_range(span)
    end

    test "returns expanded range for point span" do
      span = Position.new(5, 10)

      assert {5, 10, 11} = Position.single_line_range(span)
    end

    test "returns nil for multi-line span" do
      span = Position.new(5, 10, 6, 5)

      assert nil == Position.single_line_range(span)
    end

    test "returns nil when end_line differs" do
      span = Position.new(5, 1, 10, 1)

      assert nil == Position.single_line_range(span)
    end
  end

  describe "Span.Search" do
    test "creates search span with required options" do
      span = Search.new(line: 5, pattern: "foo")

      assert %Search{
               line: 5,
               pattern: "foo",
               after_column: 1,
               max_lines: 1
             } = span
    end

    test "accepts after_column option" do
      span = Search.new(line: 5, pattern: "foo", after_column: 10)

      assert %Search{after_column: 10} = span
    end

    test "accepts max_lines option" do
      span = Search.new(line: 5, pattern: "foo", max_lines: 5)

      assert %Search{max_lines: 5} = span
    end

    test "raises when line is missing" do
      assert_raise KeyError, fn ->
        Search.new(pattern: "foo")
      end
    end

    test "raises when pattern is missing" do
      assert_raise KeyError, fn ->
        Search.new(line: 5)
      end
    end
  end

  describe "Search.resolve/2" do
    test "returns point span when source is nil" do
      search = Search.new(line: 5, pattern: "foo", after_column: 10)

      result = Search.resolve(search, nil)

      assert %Position{start_line: 5, start_column: 10} = result
    end

    test "finds pattern on the specified line" do
      source = Source.from_string("test", "line1\nfoo bar\nline3")
      search = Search.new(line: 2, pattern: "bar")

      result = Search.resolve(search, source)

      assert %Position{
               start_line: 2,
               start_column: 5,
               end_line: 2,
               end_column: 8
             } = result
    end

    test "respects after_column option" do
      source = Source.from_string("test", "foo foo foo")
      search = Search.new(line: 1, pattern: "foo", after_column: 5)

      result = Search.resolve(search, source)

      assert %Position{start_line: 1, start_column: 5, end_column: 8} = result
    end

    test "searches across multiple lines with max_lines" do
      source = Source.from_string("test", "line1\nline2\ntarget\nline4")
      search = Search.new(line: 1, pattern: "target", max_lines: 5)

      result = Search.resolve(search, source)

      assert %Position{start_line: 3, start_column: 1, end_column: 7} = result
    end

    test "returns fallback when pattern not found" do
      source = Source.from_string("test", "line1\nline2\nline3")
      search = Search.new(line: 1, pattern: "notfound", after_column: 5)

      result = Search.resolve(search, source)

      assert %Position{start_line: 1, start_column: 5} = result
    end

    test "returns fallback when line doesn't exist" do
      source = Source.from_string("test", "line1")
      search = Search.new(line: 100, pattern: "foo")

      result = Search.resolve(search, source)

      assert %Position{start_line: 100, start_column: 1} = result
    end

    test "stops searching after max_lines exhausted" do
      source = Source.from_string("test", "a\nb\nc\nd\ntarget")
      search = Search.new(line: 1, pattern: "target", max_lines: 2)

      result = Search.resolve(search, source)

      # Should not find target since it's on line 5 and max_lines is 2.
      assert %Position{start_line: 1, start_column: 1, end_line: nil} = result
    end
  end

  describe "Span convenience functions" do
    test "byte/2 creates byte span" do
      span = Span.byte(42, 10)

      assert %Byte{start: 42, length: 10} = span
    end

    test "position/2 creates point span" do
      span = Span.position(5, 10)

      assert %Position{start_line: 5, start_column: 10, end_line: nil} = span
    end

    test "position/4 creates range span" do
      span = Span.position(5, 10, 5, 20)

      assert %Position{start_line: 5, start_column: 10, end_line: 5, end_column: 20} = span
    end

    test "search/1 creates search span" do
      span = Span.search(line: 5, pattern: "foo")

      assert %Search{line: 5, pattern: "foo"} = span
    end
  end

  describe "property tests for Span.Position" do
    property "point? is true iff both end fields are nil" do
      check all(
              line <- positive_integer(),
              col <- positive_integer(),
              end_line <- one_of([constant(nil), positive_integer()]),
              end_col <- one_of([constant(nil), positive_integer()])
            ) do
        span = %Position{
          start_line: line,
          start_column: col,
          end_line: end_line,
          end_column: end_col
        }

        expected_point = is_nil(end_line) and is_nil(end_col)
        assert Position.point?(span) == expected_point
      end
    end

    property "single_line_range returns nil for multi-line spans" do
      check all(
              start_line <- positive_integer(),
              col <- positive_integer(),
              # Generate offset >= 1 to guarantee end_line != start_line.
              line_offset <- positive_integer(),
              end_col <- positive_integer()
            ) do
        end_line = start_line + line_offset
        span = Position.new(start_line, col, end_line, end_col)

        assert Position.single_line_range(span) == nil
      end
    end

    property "single_line_range returns same line for single-line spans" do
      check all(
              line <- positive_integer(),
              start_col <- positive_integer(),
              # Generate offset >= 1 to guarantee end_col > start_col.
              col_offset <- positive_integer()
            ) do
        end_col = start_col + col_offset
        span = Position.new(line, start_col, line, end_col)

        {result_line, result_start, result_end} = Position.single_line_range(span)
        assert result_line == line
        assert result_start == start_col
        assert result_end == end_col
      end
    end
  end

  describe "property tests for Span.Byte" do
    property "byte span preserves start and length" do
      check all(
              start <- non_negative_integer(),
              length <- positive_integer()
            ) do
        span = Byte.new(start, length)

        assert span.start == start
        assert span.length == length
      end
    end
  end

  describe "property tests for Search.resolve" do
    property "resolve always returns a Position span" do
      check all(
              line <- positive_integer(),
              pattern <- string(:alphanumeric, min_length: 1),
              content <- string(:alphanumeric)
            ) do
        source = Source.from_string("test", content)
        search = Search.new(line: line, pattern: pattern)

        result = Search.resolve(search, source)

        assert %Position{} = result
        assert result.start_line >= 1
        assert result.start_column >= 1
      end
    end

    property "resolve with nil source always returns point at line, after_column" do
      check all(
              line <- positive_integer(),
              after_col <- positive_integer(),
              pattern <- string(:alphanumeric, min_length: 1)
            ) do
        search = Search.new(line: line, pattern: pattern, after_column: after_col)

        result = Search.resolve(search, nil)

        assert %Position{start_line: ^line, start_column: ^after_col} = result
        assert Position.point?(result)
      end
    end
  end
end
