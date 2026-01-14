defmodule PentimentTest do
  use ExUnit.Case

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
  end
end
