defmodule Pentiment.SourceTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Pentiment.Source

  describe "from_string/2" do
    test "creates source with name and content" do
      source = Source.from_string("test.ex", "hello world")

      assert %Source{name: "test.ex", content: "hello world"} = source
    end

    test "splits content into lines" do
      source = Source.from_string("test.ex", "line1\nline2\nline3")

      assert Source.lines(source) == ["line1", "line2", "line3"]
    end

    test "handles empty content" do
      source = Source.from_string("test.ex", "")

      assert Source.content(source) == ""
      assert Source.lines(source) == [""]
    end

    test "handles single line without newline" do
      source = Source.from_string("test.ex", "single line")

      assert Source.lines(source) == ["single line"]
    end

    test "handles trailing newline" do
      source = Source.from_string("test.ex", "line1\nline2\n")

      assert Source.lines(source) == ["line1", "line2", ""]
    end
  end

  describe "named/1" do
    test "creates source with just a name" do
      source = Source.named("lib/app.ex")

      assert %Source{name: "lib/app.ex", content: nil, lines: nil} = source
    end

    test "has no content" do
      source = Source.named("lib/app.ex")

      refute Source.has_content?(source)
    end
  end

  describe "from_file/1" do
    @tag :tmp_dir
    test "reads content from file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.ex")
      File.write!(path, "defmodule Test do\n  :ok\nend")

      source = Source.from_file(path)

      assert source.name == path
      assert source.content == "defmodule Test do\n  :ok\nend"
      assert Source.lines(source) == ["defmodule Test do", "  :ok", "end"]
    end

    test "raises for non-existent file" do
      assert_raise File.Error, fn ->
        Source.from_file("/nonexistent/path/file.ex")
      end
    end
  end

  describe "name/1" do
    test "returns the source name" do
      source = Source.from_string("my_file.ex", "content")

      assert Source.name(source) == "my_file.ex"
    end
  end

  describe "content/1" do
    test "returns content for source with content" do
      source = Source.from_string("test.ex", "the content")

      assert Source.content(source) == "the content"
    end

    test "returns nil for named source" do
      source = Source.named("test.ex")

      assert Source.content(source) == nil
    end
  end

  describe "lines/1" do
    test "returns lines for source with content" do
      source = Source.from_string("test.ex", "a\nb\nc")

      assert Source.lines(source) == ["a", "b", "c"]
    end

    test "returns nil for named source" do
      source = Source.named("test.ex")

      assert Source.lines(source) == nil
    end
  end

  describe "line/2" do
    test "returns specific line (1-indexed)" do
      source = Source.from_string("test.ex", "line1\nline2\nline3")

      assert Source.line(source, 1) == "line1"
      assert Source.line(source, 2) == "line2"
      assert Source.line(source, 3) == "line3"
    end

    test "returns nil for out-of-bounds line" do
      source = Source.from_string("test.ex", "line1\nline2")

      # Lines beyond the file return nil.
      assert Source.line(source, 100) == nil
    end

    test "raises for invalid line number (0)" do
      source = Source.from_string("test.ex", "line1\nline2")

      # Line numbers are 1-indexed; 0 is invalid and fails the guard clause.
      assert_raise FunctionClauseError, fn ->
        Source.line(source, 0)
      end
    end

    test "returns nil for named source" do
      source = Source.named("test.ex")

      assert Source.line(source, 1) == nil
    end

    test "handles empty lines" do
      source = Source.from_string("test.ex", "a\n\nb")

      assert Source.line(source, 1) == "a"
      assert Source.line(source, 2) == ""
      assert Source.line(source, 3) == "b"
    end
  end

  describe "line_range/3" do
    test "returns range of lines" do
      source = Source.from_string("test.ex", "a\nb\nc\nd\ne")

      assert Source.line_range(source, 2, 4) == [{2, "b"}, {3, "c"}, {4, "d"}]
    end

    test "returns single line when start equals end" do
      source = Source.from_string("test.ex", "a\nb\nc")

      assert Source.line_range(source, 2, 2) == [{2, "b"}]
    end

    test "handles partial range at end of file" do
      source = Source.from_string("test.ex", "a\nb")

      assert Source.line_range(source, 1, 5) == [{1, "a"}, {2, "b"}]
    end

    test "returns empty list for named source" do
      source = Source.named("test.ex")

      assert Source.line_range(source, 1, 3) == []
    end

    test "returns empty list when start > end" do
      source = Source.from_string("test.ex", "a\nb\nc")

      # This case raises due to guard clause.
      assert_raise FunctionClauseError, fn ->
        Source.line_range(source, 3, 1)
      end
    end
  end

  describe "has_content?/1" do
    test "returns true for source with content" do
      source = Source.from_string("test.ex", "content")

      assert Source.has_content?(source)
    end

    test "returns true for empty string content" do
      source = Source.from_string("test.ex", "")

      assert Source.has_content?(source)
    end

    test "returns false for named source" do
      source = Source.named("test.ex")

      refute Source.has_content?(source)
    end
  end

  describe "line_count/1" do
    test "returns number of lines" do
      source = Source.from_string("test.ex", "a\nb\nc")

      assert Source.line_count(source) == 3
    end

    test "returns 1 for single line" do
      source = Source.from_string("test.ex", "single")

      assert Source.line_count(source) == 1
    end

    test "counts trailing empty line" do
      source = Source.from_string("test.ex", "a\nb\n")

      assert Source.line_count(source) == 3
    end

    test "returns nil for named source" do
      source = Source.named("test.ex")

      assert Source.line_count(source) == nil
    end
  end

  describe "byte_to_position/2" do
    test "returns position for offset at start of content" do
      source = Source.from_string("test", "hello world")

      assert Source.byte_to_position(source, 0) == {1, 1}
    end

    test "returns position for offset within first line" do
      source = Source.from_string("test", "hello world")

      assert Source.byte_to_position(source, 6) == {1, 7}
    end

    test "returns position at start of second line" do
      source = Source.from_string("test", "hello\nworld")

      # Byte 5 is the newline, byte 6 is 'w' on line 2.
      assert Source.byte_to_position(source, 6) == {2, 1}
    end

    test "returns position for multi-line content" do
      source = Source.from_string("test", "line1\nline2\nline3")

      assert Source.byte_to_position(source, 0) == {1, 1}
      assert Source.byte_to_position(source, 5) == {1, 6}
      assert Source.byte_to_position(source, 6) == {2, 1}
      assert Source.byte_to_position(source, 12) == {3, 1}
    end

    test "returns nil for offset beyond content" do
      source = Source.from_string("test", "hello")

      assert Source.byte_to_position(source, 100) == nil
    end

    test "returns nil for named source without content" do
      source = Source.named("test.ex")

      assert Source.byte_to_position(source, 0) == nil
    end

    test "returns nil for negative offset" do
      source = Source.from_string("test", "hello")

      assert Source.byte_to_position(source, -1) == nil
    end

    test "handles empty content" do
      source = Source.from_string("test", "")

      assert Source.byte_to_position(source, 0) == {1, 1}
      assert Source.byte_to_position(source, 1) == nil
    end

    test "handles offset at exact end of content" do
      source = Source.from_string("test", "hello")

      # Offset 5 is just past the last character, but still valid for end positions.
      assert Source.byte_to_position(source, 5) == {1, 6}
    end

    test "handles multi-byte UTF-8 characters" do
      # "héllo" where é is 2 bytes (UTF-8).
      source = Source.from_string("test", "héllo")

      assert Source.byte_to_position(source, 0) == {1, 1}
      # 'h' is at byte 0, 'é' spans bytes 1-2.
      assert Source.byte_to_position(source, 1) == {1, 2}
      # Byte 3 is 'l'.
      assert Source.byte_to_position(source, 3) == {1, 3}
    end

    test "handles newlines correctly across multiple lines" do
      source = Source.from_string("test", "a\nb\nc")

      # a is byte 0, \n is byte 1, b is byte 2, \n is byte 3, c is byte 4.
      assert Source.byte_to_position(source, 0) == {1, 1}
      assert Source.byte_to_position(source, 1) == {1, 2}
      assert Source.byte_to_position(source, 2) == {2, 1}
      assert Source.byte_to_position(source, 3) == {2, 2}
      assert Source.byte_to_position(source, 4) == {3, 1}
    end
  end

  describe "property tests" do
    property "line_count equals length of lines list" do
      check all(content <- string(:printable)) do
        source = Source.from_string("test", content)
        lines = Source.lines(source)
        count = Source.line_count(source)

        assert count == length(lines)
      end
    end

    property "line/2 returns element at (n-1) index of lines" do
      check all(
              lines <- list_of(string(:alphanumeric), min_length: 1, max_length: 10),
              n <- integer(1..length(lines))
            ) do
        content = Enum.join(lines, "\n")
        source = Source.from_string("test", content)

        assert Source.line(source, n) == Enum.at(lines, n - 1)
      end
    end

    property "line_range returns consecutive tuples with correct line numbers" do
      check all(
              lines <- list_of(string(:alphanumeric), min_length: 3, max_length: 10),
              start <- integer(1..length(lines)),
              len <- integer(1..min(3, length(lines) - start + 1))
            ) do
        content = Enum.join(lines, "\n")
        source = Source.from_string("test", content)
        end_line = start + len - 1

        result = Source.line_range(source, start, end_line)

        # Check line numbers are consecutive.
        line_nums = Enum.map(result, fn {n, _} -> n end)
        assert line_nums == Enum.to_list(start..end_line)
      end
    end

    property "has_content? is true iff content is not nil" do
      check all(
              name <- string(:alphanumeric, min_length: 1),
              has_content? <- boolean()
            ) do
        source =
          if has_content? do
            Source.from_string(name, "content")
          else
            Source.named(name)
          end

        assert Source.has_content?(source) == has_content?
      end
    end

    property "byte_to_position returns nil for offset beyond content" do
      check all(content <- string(:printable, min_length: 1)) do
        source = Source.from_string("test", content)
        beyond_offset = byte_size(content) + 1

        assert Source.byte_to_position(source, beyond_offset) == nil
      end
    end

    property "byte_to_position at offset 0 returns {1, 1} for non-empty content" do
      check all(content <- string(:printable, min_length: 1)) do
        source = Source.from_string("test", content)

        assert Source.byte_to_position(source, 0) == {1, 1}
      end
    end

    property "byte_to_position returns valid line and column" do
      check all(
              content <- string(:printable, min_length: 1),
              offset <- integer(0..(byte_size(content) - 1))
            ) do
        source = Source.from_string("test", content)
        result = Source.byte_to_position(source, offset)

        assert {line, col} = result
        assert line >= 1
        assert col >= 1
      end
    end
  end
end
