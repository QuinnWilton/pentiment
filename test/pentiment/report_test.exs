defmodule Pentiment.ReportTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Pentiment.{Diagnostic, Label, Report, Span}

  describe "build/2" do
    test "creates report with severity and message" do
      report = Report.build(:error, "Something went wrong")

      assert %Report{severity: :error, message: "Something went wrong"} = report
    end

    test "accepts all severity levels" do
      for severity <- [:error, :warning, :info, :hint] do
        report = Report.build(severity, "msg")
        assert report.severity == severity
      end
    end

    test "initializes with empty collections" do
      report = Report.build(:error, "msg")

      assert report.labels == []
      assert report.help == []
      assert report.notes == []
      assert report.code == nil
      assert report.source == nil
    end
  end

  describe "error/1" do
    test "creates error report" do
      report = Report.error("Error message")

      assert report.severity == :error
      assert report.message == "Error message"
    end
  end

  describe "warning/1" do
    test "creates warning report" do
      report = Report.warning("Warning message")

      assert report.severity == :warning
      assert report.message == "Warning message"
    end
  end

  describe "info/1" do
    test "creates info report" do
      report = Report.info("Info message")

      assert report.severity == :info
      assert report.message == "Info message"
    end
  end

  describe "hint/1" do
    test "creates hint report" do
      report = Report.hint("Hint message")

      assert report.severity == :hint
      assert report.message == "Hint message"
    end
  end

  describe "with_code/2" do
    test "sets error code" do
      report =
        Report.error("msg")
        |> Report.with_code("E001")

      assert report.code == "E001"
    end

    test "overwrites existing code" do
      report =
        Report.error("msg")
        |> Report.with_code("E001")
        |> Report.with_code("E002")

      assert report.code == "E002"
    end
  end

  describe "with_source/2" do
    test "sets source" do
      report =
        Report.error("msg")
        |> Report.with_source("lib/app.ex")

      assert report.source == "lib/app.ex"
    end

    test "overwrites existing source" do
      report =
        Report.error("msg")
        |> Report.with_source("old.ex")
        |> Report.with_source("new.ex")

      assert report.source == "new.ex"
    end
  end

  describe "with_label/2" do
    test "adds single label" do
      label = Label.primary(Span.position(1, 1), "error")

      report =
        Report.error("msg")
        |> Report.with_label(label)

      assert report.labels == [label]
    end

    test "appends to existing labels" do
      label1 = Label.primary(Span.position(1, 1), "first")
      label2 = Label.secondary(Span.position(2, 1), "second")

      report =
        Report.error("msg")
        |> Report.with_label(label1)
        |> Report.with_label(label2)

      assert report.labels == [label1, label2]
    end
  end

  describe "with_labels/2" do
    test "adds multiple labels at once" do
      label1 = Label.primary(Span.position(1, 1), "first")
      label2 = Label.secondary(Span.position(2, 1), "second")

      report =
        Report.error("msg")
        |> Report.with_labels([label1, label2])

      assert report.labels == [label1, label2]
    end

    test "appends to existing labels" do
      existing = Label.primary(Span.position(1, 1), "existing")
      new1 = Label.secondary(Span.position(2, 1), "new1")
      new2 = Label.secondary(Span.position(3, 1), "new2")

      report =
        Report.error("msg")
        |> Report.with_label(existing)
        |> Report.with_labels([new1, new2])

      assert report.labels == [existing, new1, new2]
    end

    test "handles empty list" do
      report =
        Report.error("msg")
        |> Report.with_labels([])

      assert report.labels == []
    end
  end

  describe "with_help/2" do
    test "adds help message" do
      report =
        Report.error("msg")
        |> Report.with_help("Try this instead")

      assert report.help == ["Try this instead"]
    end

    test "appends multiple help messages" do
      report =
        Report.error("msg")
        |> Report.with_help("First suggestion")
        |> Report.with_help("Second suggestion")

      assert report.help == ["First suggestion", "Second suggestion"]
    end
  end

  describe "with_note/2" do
    test "adds note" do
      report =
        Report.error("msg")
        |> Report.with_note("Additional context")

      assert report.notes == ["Additional context"]
    end

    test "appends multiple notes" do
      report =
        Report.error("msg")
        |> Report.with_note("First note")
        |> Report.with_note("Second note")

      assert report.notes == ["First note", "Second note"]
    end
  end

  describe "builder chaining" do
    test "supports full builder chain" do
      label = Label.primary(Span.position(5, 10), "error here")

      report =
        Report.error("Type mismatch")
        |> Report.with_code("T001")
        |> Report.with_source("app.ex")
        |> Report.with_label(label)
        |> Report.with_note("Expected integer")
        |> Report.with_help("Use trunc/1")

      assert report.message == "Type mismatch"
      assert report.severity == :error
      assert report.code == "T001"
      assert report.source == "app.ex"
      assert report.labels == [label]
      assert report.notes == ["Expected integer"]
      assert report.help == ["Use trunc/1"]
    end
  end

  describe "Diagnostic protocol implementation" do
    test "message/1 returns message" do
      report = Report.error("The message")

      assert Diagnostic.message(report) == "The message"
    end

    test "code/1 returns code" do
      report = Report.error("msg") |> Report.with_code("E001")

      assert Diagnostic.code(report) == "E001"
    end

    test "code/1 returns nil when not set" do
      report = Report.error("msg")

      assert Diagnostic.code(report) == nil
    end

    test "severity/1 returns severity" do
      for severity <- [:error, :warning, :info, :hint] do
        report = Report.build(severity, "msg")
        assert Diagnostic.severity(report) == severity
      end
    end

    test "source/1 returns source" do
      report = Report.error("msg") |> Report.with_source("file.ex")

      assert Diagnostic.source(report) == "file.ex"
    end

    test "source/1 returns nil when not set" do
      report = Report.error("msg")

      assert Diagnostic.source(report) == nil
    end

    test "labels/1 returns labels" do
      label = Label.primary(Span.position(1, 1), "msg")
      report = Report.error("msg") |> Report.with_label(label)

      assert Diagnostic.labels(report) == [label]
    end

    test "labels/1 returns empty list when no labels" do
      report = Report.error("msg")

      assert Diagnostic.labels(report) == []
    end

    test "help/1 returns help messages" do
      report =
        Report.error("msg")
        |> Report.with_help("help1")
        |> Report.with_help("help2")

      assert Diagnostic.help(report) == ["help1", "help2"]
    end

    test "notes/1 returns notes" do
      report =
        Report.error("msg")
        |> Report.with_note("note1")
        |> Report.with_note("note2")

      assert Diagnostic.notes(report) == ["note1", "note2"]
    end
  end

  describe "property tests" do
    property "severity constructors produce correct severity" do
      severity_map = %{
        error: &Report.error/1,
        warning: &Report.warning/1,
        info: &Report.info/1,
        hint: &Report.hint/1
      }

      check all(
              severity <- member_of([:error, :warning, :info, :hint]),
              message <- string(:alphanumeric, min_length: 1)
            ) do
        constructor = Map.fetch!(severity_map, severity)
        report = constructor.(message)

        assert report.severity == severity
        assert report.message == message
      end
    end

    property "with_label preserves order" do
      check all(
              n <- integer(1..5),
              messages <- list_of(string(:alphanumeric), length: n)
            ) do
        labels = Enum.map(messages, &Label.primary(Span.position(1, 1), &1))

        report =
          Enum.reduce(labels, Report.error("msg"), fn label, acc ->
            Report.with_label(acc, label)
          end)

        assert report.labels == labels
      end
    end

    property "with_labels appends all labels" do
      check all(
              existing_count <- integer(0..3),
              new_count <- integer(1..5)
            ) do
        existing =
          if existing_count > 0 do
            for i <- 1..existing_count do
              Label.primary(Span.position(i, 1), "existing #{i}")
            end
          else
            []
          end

        new =
          for i <- 1..new_count do
            Label.secondary(Span.position(i + 10, 1), "new #{i}")
          end

        report =
          Report.error("msg")
          |> Report.with_labels(existing)
          |> Report.with_labels(new)

        assert report.labels == existing ++ new
      end
    end

    property "with_help and with_note preserve order" do
      check all(
              help_msgs <- list_of(string(:alphanumeric, min_length: 1), max_length: 5),
              note_msgs <- list_of(string(:alphanumeric, min_length: 1), max_length: 5)
            ) do
        report =
          Report.error("msg")
          |> then(fn r -> Enum.reduce(help_msgs, r, &Report.with_help(&2, &1)) end)
          |> then(fn r -> Enum.reduce(note_msgs, r, &Report.with_note(&2, &1)) end)

        assert report.help == help_msgs
        assert report.notes == note_msgs
      end
    end

    property "Diagnostic protocol matches struct fields" do
      check all(
              message <- string(:alphanumeric, min_length: 1),
              code <- one_of([constant(nil), string(:alphanumeric, min_length: 1)]),
              source <- one_of([constant(nil), string(:alphanumeric, min_length: 1)]),
              severity <- member_of([:error, :warning, :info, :hint])
            ) do
        report = Report.build(severity, message)
        report = if code, do: Report.with_code(report, code), else: report
        report = if source, do: Report.with_source(report, source), else: report

        assert Diagnostic.message(report) == message
        assert Diagnostic.code(report) == code
        assert Diagnostic.source(report) == source
        assert Diagnostic.severity(report) == severity
      end
    end
  end
end
