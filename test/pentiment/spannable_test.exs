defmodule Pentiment.SpannableTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Pentiment.{Span, Spannable}

  describe "Spannable for Span.Byte" do
    test "returns the span unchanged" do
      span = Span.byte(42, 10)

      assert Spannable.to_span(span) == span
    end
  end

  describe "Spannable for Span.Position" do
    test "returns the span unchanged" do
      span = Span.position(5, 10, 5, 20)

      assert Spannable.to_span(span) == span
    end

    test "returns point span unchanged" do
      span = Span.position(5, 10)

      assert Spannable.to_span(span) == span
    end
  end

  describe "Spannable for Tuple (2-tuple)" do
    test "converts to byte span" do
      result = Spannable.to_span({42, 10})

      assert %Span.Byte{start: 42, length: 10} = result
    end

    test "handles start of 0" do
      result = Spannable.to_span({0, 5})

      assert %Span.Byte{start: 0, length: 5} = result
    end

    test "raises for invalid 2-tuple (negative start)" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span({-1, 5})
      end
    end

    test "raises for invalid 2-tuple (zero length)" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span({0, 0})
      end
    end
  end

  describe "Spannable for Tuple (4-tuple)" do
    test "converts to position span" do
      result = Spannable.to_span({5, 10, 5, 20})

      assert %Span.Position{
               start_line: 5,
               start_column: 10,
               end_line: 5,
               end_column: 20
             } = result
    end

    test "handles multi-line spans" do
      result = Spannable.to_span({5, 1, 10, 15})

      assert %Span.Position{
               start_line: 5,
               start_column: 1,
               end_line: 10,
               end_column: 15
             } = result
    end

    test "raises for invalid 4-tuple (line < 1)" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span({0, 1, 1, 5})
      end
    end

    test "raises for invalid 4-tuple (column < 1)" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span({1, 0, 1, 5})
      end
    end
  end

  describe "Spannable for Tuple (invalid tuples)" do
    test "raises for 3-tuple" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span({1, 2, 3})
      end
    end

    test "raises for 1-tuple" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span({1})
      end
    end

    test "raises for 5-tuple" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span({1, 2, 3, 4, 5})
      end
    end

    test "raises for empty tuple" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span({})
      end
    end
  end

  describe "Spannable for Range" do
    test "converts ascending range to byte span" do
      result = Spannable.to_span(10..20)

      assert %Span.Byte{start: 10, length: 11} = result
    end

    test "handles range starting at 0" do
      result = Spannable.to_span(0..5)

      assert %Span.Byte{start: 0, length: 6} = result
    end

    test "handles single-element range" do
      result = Spannable.to_span(5..5)

      assert %Span.Byte{start: 5, length: 1} = result
    end

    test "raises for descending range" do
      assert_raise ArgumentError, fn ->
        # Explicit descending range to avoid Elixir 1.19 warning.
        Spannable.to_span(20..10//-1)
      end
    end

    test "raises for range starting below 0" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span(-5..10)
      end
    end

    test "raises for range with step != 1" do
      assert_raise ArgumentError, fn ->
        Spannable.to_span(0..10//2)
      end
    end
  end

  describe "property tests for 2-tuple" do
    property "2-tuple conversion preserves start and length" do
      check all(
              start <- non_negative_integer(),
              length <- positive_integer()
            ) do
        result = Spannable.to_span({start, length})

        assert %Span.Byte{} = result
        assert result.start == start
        assert result.length == length
      end
    end
  end

  describe "property tests for 4-tuple" do
    property "4-tuple conversion preserves all fields" do
      check all(
              start_line <- positive_integer(),
              start_col <- positive_integer(),
              end_line <- positive_integer(),
              end_col <- positive_integer()
            ) do
        result = Spannable.to_span({start_line, start_col, end_line, end_col})

        assert %Span.Position{} = result
        assert result.start_line == start_line
        assert result.start_column == start_col
        assert result.end_line == end_line
        assert result.end_column == end_col
      end
    end
  end

  describe "property tests for Range" do
    property "range conversion produces correct length" do
      check all(
              first <- non_negative_integer(),
              len <- positive_integer()
            ) do
        last = first + len - 1
        result = Spannable.to_span(first..last)

        assert %Span.Byte{} = result
        assert result.start == first
        assert result.length == len
      end
    end
  end

  describe "property tests for identity" do
    property "Byte span is identity" do
      check all(
              start <- non_negative_integer(),
              length <- positive_integer()
            ) do
        span = Span.byte(start, length)

        assert Spannable.to_span(span) === span
      end
    end

    property "Position span is identity" do
      check all(
              line <- positive_integer(),
              col <- positive_integer(),
              end_line <- one_of([constant(nil), positive_integer()]),
              end_col <- one_of([constant(nil), positive_integer()])
            ) do
        span = %Span.Position{
          start_line: line,
          start_column: col,
          end_line: end_line,
          end_column: end_col
        }

        assert Spannable.to_span(span) === span
      end
    end
  end
end
