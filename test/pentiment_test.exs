defmodule PentimentTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Pentiment.{Label, Report, Source, Span}

  describe "format/3" do
    test "formats a simple error" do
      report =
        Report.error("Something went wrong")
        |> Report.with_code("E001")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(5, 10), "error here"))

      source =
        Source.from_string("test.ex", """
        defmodule Test do
          def foo do
            :ok
          end
          x = 1 + 2
        end
        """)

      result = Pentiment.format(report, source, colors: false)

      assert result =~ "error[E001]: Something went wrong"
      assert result =~ "test.ex:5:10"
      assert result =~ "error here"
    end

    test "formats error with notes and help" do
      report =
        Report.error("Type mismatch")
        |> Report.with_code("T001")
        |> Report.with_source("app.ex")
        |> Report.with_label(Label.primary(Span.position(3, 5), "found `string`"))
        |> Report.with_note("expected `integer` based on context")
        |> Report.with_help("use `String.to_integer/1` to convert")

      source =
        Source.from_string("app.ex", """
        defmodule App do
          def run do
            "not a number"
          end
        end
        """)

      result = Pentiment.format(report, source, colors: false)

      assert result =~ "error[T001]: Type mismatch"
      assert result =~ "note: expected `integer` based on context"
      assert result =~ "help: use `String.to_integer/1` to convert"
    end

    test "formats warning" do
      report =
        Report.warning("Unused variable `x`")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(2, 3), "defined but never used"))

      source =
        Source.from_string("test.ex", """
        def foo do
          x = 1
          :ok
        end
        """)

      result = Pentiment.format(report, source, colors: false)

      assert result =~ "warning: Unused variable `x`"
    end
  end

  describe "format_compact/1" do
    test "formats as single line" do
      report =
        Report.error("Parse error")
        |> Report.with_code("P001")
        |> Report.with_source("input.txt")
        |> Report.with_label(Label.primary(Span.position(10, 5), "unexpected token"))

      result = Pentiment.format_compact(report)

      assert result == "[P001] Parse error (input.txt:10:5)"
    end

    test "formats without code" do
      report =
        Report.error("Something failed")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))

      result = Pentiment.format_compact(report)

      assert result == "Something failed (test.ex:1:1)"
    end
  end

  describe "format_all/3" do
    test "formats multiple diagnostics" do
      error1 =
        Report.error("First error")
        |> Report.with_code("E001")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))

      error2 =
        Report.warning("A warning")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(2, 1), "here"))

      source = Source.from_string("test.ex", "line1\nline2\nline3")

      result = Pentiment.format_all([error1, error2], source, colors: false)

      assert result =~ "error[E001]: First error"
      assert result =~ "warning: A warning"
      assert result =~ "1 error, 1 warning emitted"
    end

    test "formats empty list" do
      source = Source.from_string("test.ex", "content")

      result = Pentiment.format_all([], source, colors: false)

      assert result == ""
    end

    test "formats single diagnostic" do
      report =
        Report.error("Single error")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))

      source = Source.from_string("test.ex", "content")

      result = Pentiment.format_all([report], source, colors: false)

      assert result =~ "error: Single error"
      assert result =~ "1 error emitted"
    end

    test "correctly pluralizes summary" do
      errors =
        for i <- 1..3 do
          Report.error("Error #{i}")
          |> Report.with_source("test.ex")
          |> Report.with_label(Label.primary(Span.position(i, 1), "here"))
        end

      warnings =
        for i <- 1..2 do
          Report.warning("Warning #{i}")
          |> Report.with_source("test.ex")
          |> Report.with_label(Label.primary(Span.position(i + 3, 1), "here"))
        end

      source = Source.from_string("test.ex", "l1\nl2\nl3\nl4\nl5\nl6")

      result = Pentiment.format_all(errors ++ warnings, source, colors: false)

      assert result =~ "3 errors, 2 warnings emitted"
    end
  end

  describe "format/3 edge cases" do
    test "formats info severity" do
      report =
        Report.info("Information message")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))

      source = Source.from_string("test.ex", "content")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "info: Information message"
    end

    test "formats hint severity" do
      report =
        Report.hint("Hint message")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))

      source = Source.from_string("test.ex", "content")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "hint: Hint message"
    end

    test "handles report without labels" do
      report =
        Report.error("No labels")
        |> Report.with_source("test.ex")

      source = Source.from_string("test.ex", "content")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "error: No labels"
    end

    test "handles report without source" do
      report =
        Report.error("No source")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))

      source = Source.from_string("test.ex", "content")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "error: No source"
    end

    test "handles multiple labels on same line" do
      report =
        Report.error("Multiple labels")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1, 1, 5), "first"))
        |> Report.with_label(Label.secondary(Span.position(1, 10, 1, 15), "second"))

      source = Source.from_string("test.ex", "hello world foo bar")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "first"
      assert result =~ "second"
    end

    test "handles multi-line spans" do
      report =
        Report.error("Multi-line span")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1, 3, 5), "spans lines"))

      source = Source.from_string("test.ex", "line1\nline2\nline3")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "spans lines"
    end

    test "handles multiple notes" do
      report =
        Report.error("With notes")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))
        |> Report.with_note("First note")
        |> Report.with_note("Second note")

      source = Source.from_string("test.ex", "content")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "note: First note"
      assert result =~ "note: Second note"
    end

    test "handles multiple help messages" do
      report =
        Report.error("With help")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))
        |> Report.with_help("First suggestion")
        |> Report.with_help("Second suggestion")

      source = Source.from_string("test.ex", "content")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "help: First suggestion"
      assert result =~ "help: Second suggestion"
    end

    test "handles source as map" do
      report =
        Report.error("Map source")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))

      sources = %{"test.ex" => "content from map"}
      result = Pentiment.format(report, sources, colors: false)

      assert result =~ "error: Map source"
      assert result =~ "content from map"
    end

    test "resolves search spans" do
      report =
        Report.error("Search span")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.search(line: 1, pattern: "target"), "found it"))

      source = Source.from_string("test.ex", "prefix target suffix")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "found it"
    end

    test "resolves byte spans on single line" do
      report =
        Report.error("Byte span error")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.byte(6, 5), "this is 'world'"))

      source = Source.from_string("test.ex", "hello world")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "error: Byte span error"
      assert result =~ "test.ex:1:7"
      assert result =~ "this is 'world'"
      assert result =~ "hello world"
    end

    test "resolves byte spans across multiple lines" do
      report =
        Report.error("Multi-line byte span")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.byte(6, 5), "spans to second line"))

      source = Source.from_string("test.ex", "hello\nworld\nfoo")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "error: Multi-line byte span"
      assert result =~ "test.ex:2:1"
      assert result =~ "spans to second line"
    end

    test "handles byte span with nil source (fallback)" do
      report =
        Report.error("No source")
        |> Report.with_source("missing.ex")
        |> Report.with_label(Label.primary(Span.byte(10, 5), "label"))

      # Source name doesn't match, so nil is used.
      source = Source.from_string("other.ex", "content")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "error: No source"
      # Should fall back to line 1, column 1.
      assert result =~ "line 1:1"
    end

    test "handles mixed Position and Byte spans in same diagnostic" do
      report =
        Report.error("Mixed spans")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.position(1, 1, 1, 5), "position span"))
        |> Report.with_label(Label.secondary(Span.byte(6, 5), "byte span"))

      source = Source.from_string("test.ex", "hello world foo bar")
      result = Pentiment.format(report, source, colors: false)

      assert result =~ "position span"
      assert result =~ "byte span"
    end

    test "handles byte span with invalid offset (fallback)" do
      report =
        Report.error("Invalid offset")
        |> Report.with_source("test.ex")
        |> Report.with_label(Label.primary(Span.byte(100, 5), "unreachable"))

      source = Source.from_string("test.ex", "hello")
      result = Pentiment.format(report, source, colors: false)

      # Should fall back gracefully.
      assert result =~ "error: Invalid offset"
    end
  end

  describe "format_compact/1 edge cases" do
    test "handles report without labels" do
      report =
        Report.error("No labels")
        |> Report.with_code("E001")
        |> Report.with_source("test.ex")

      result = Pentiment.format_compact(report)

      # No labels means no location info.
      assert result == "[E001] No labels"
    end

    test "handles report without source" do
      report =
        Report.error("No source")
        |> Report.with_code("E001")
        |> Report.with_label(Label.primary(Span.position(1, 1), "here"))

      result = Pentiment.format_compact(report)

      # Without source, uses "line" prefix.
      assert result == "[E001] No source (line 1:1)"
    end

    test "handles report without source or labels" do
      report =
        Report.error("Minimal")
        |> Report.with_code("E001")

      result = Pentiment.format_compact(report)

      assert result == "[E001] Minimal"
    end
  end

  describe "property tests" do
    property "format always returns a string containing the message" do
      check all(
              message <- string(:alphanumeric, min_length: 1),
              line <- positive_integer(),
              col <- positive_integer()
            ) do
        report =
          Report.error(message)
          |> Report.with_source("test.ex")
          |> Report.with_label(Label.primary(Span.position(line, col), "label"))

        source = Source.from_string("test.ex", String.duplicate("x", 100))
        result = Pentiment.format(report, source, colors: false)

        assert is_binary(result)
        assert result =~ message
      end
    end

    property "format_compact always returns a string containing the message" do
      check all(message <- string(:alphanumeric, min_length: 1)) do
        report = Report.error(message)
        result = Pentiment.format_compact(report)

        assert is_binary(result)
        assert result =~ message
      end
    end

    property "format_all summary counts match diagnostic list" do
      check all(
              error_count <- integer(0..3),
              warning_count <- integer(0..3),
              error_count + warning_count > 0
            ) do
        # Build errors if count > 0.
        errors =
          if error_count > 0 do
            for i <- 1..error_count do
              Report.error("Error #{i}")
              |> Report.with_source("test.ex")
              |> Report.with_label(Label.primary(Span.position(i, 1), "err"))
            end
          else
            []
          end

        # Build warnings if count > 0.
        warnings =
          if warning_count > 0 do
            for i <- 1..warning_count do
              Report.warning("Warning #{i}")
              |> Report.with_source("test.ex")
              |> Report.with_label(
                Label.primary(Span.position(i + max(error_count, 0), 1), "warn")
              )
            end
          else
            []
          end

        diagnostics = errors ++ warnings
        content = String.duplicate("line\n", error_count + warning_count + 1)
        source = Source.from_string("test.ex", content)
        result = Pentiment.format_all(diagnostics, source, colors: false)

        if error_count > 0 do
          assert result =~ "#{error_count} error"
        end

        if warning_count > 0 do
          assert result =~ "#{warning_count} warning"
        end
      end
    end
  end
end
