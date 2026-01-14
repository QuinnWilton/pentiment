defmodule Pentiment.LabelTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Pentiment.{Label, Span}

  describe "new/2" do
    test "creates label with span only" do
      span = Span.position(5, 10)
      label = Label.new(span)

      assert %Label{
               span: ^span,
               message: nil,
               priority: :primary,
               source: nil
             } = label
    end

    test "accepts message option" do
      span = Span.position(5, 10)
      label = Label.new(span, message: "error here")

      assert label.message == "error here"
    end

    test "accepts priority option" do
      span = Span.position(5, 10)
      label = Label.new(span, priority: :secondary)

      assert label.priority == :secondary
    end

    test "accepts source option" do
      span = Span.position(5, 10)
      label = Label.new(span, source: "other.ex")

      assert label.source == "other.ex"
    end

    test "accepts all options together" do
      span = Span.position(5, 10)

      label =
        Label.new(span,
          message: "the message",
          priority: :secondary,
          source: "file.ex"
        )

      assert label.message == "the message"
      assert label.priority == :secondary
      assert label.source == "file.ex"
    end
  end

  describe "primary/3" do
    test "creates primary label with message" do
      span = Span.position(5, 10)
      label = Label.primary(span, "error here")

      assert label.span == span
      assert label.message == "error here"
      assert label.priority == :primary
    end

    test "creates primary label without message" do
      span = Span.position(5, 10)
      label = Label.primary(span)

      assert label.message == nil
      assert label.priority == :primary
    end

    test "accepts source option" do
      span = Span.position(5, 10)
      label = Label.primary(span, "msg", source: "file.ex")

      assert label.source == "file.ex"
    end

    test "message can be nil explicitly" do
      span = Span.position(5, 10)
      label = Label.primary(span, nil)

      assert label.message == nil
      assert label.priority == :primary
    end
  end

  describe "secondary/3" do
    test "creates secondary label with message" do
      span = Span.position(5, 10)
      label = Label.secondary(span, "declared here")

      assert label.span == span
      assert label.message == "declared here"
      assert label.priority == :secondary
    end

    test "creates secondary label without message" do
      span = Span.position(5, 10)
      label = Label.secondary(span)

      assert label.message == nil
      assert label.priority == :secondary
    end

    test "accepts source option" do
      span = Span.position(5, 10)
      label = Label.secondary(span, "msg", source: "other.ex")

      assert label.source == "other.ex"
    end
  end

  describe "primary?/1" do
    test "returns true for primary labels" do
      label = Label.primary(Span.position(1, 1), "msg")

      assert Label.primary?(label)
    end

    test "returns false for secondary labels" do
      label = Label.secondary(Span.position(1, 1), "msg")

      refute Label.primary?(label)
    end

    test "returns true for labels created with priority: :primary" do
      label = Label.new(Span.position(1, 1), priority: :primary)

      assert Label.primary?(label)
    end
  end

  describe "secondary?/1" do
    test "returns true for secondary labels" do
      label = Label.secondary(Span.position(1, 1), "msg")

      assert Label.secondary?(label)
    end

    test "returns false for primary labels" do
      label = Label.primary(Span.position(1, 1), "msg")

      refute Label.secondary?(label)
    end

    test "returns true for labels created with priority: :secondary" do
      label = Label.new(Span.position(1, 1), priority: :secondary)

      assert Label.secondary?(label)
    end
  end

  describe "resolved_span/1" do
    test "returns Position span unchanged" do
      span = Span.position(5, 10, 5, 20)
      label = Label.primary(span, "msg")

      assert Label.resolved_span(label) == span
    end

    test "returns Byte span unchanged" do
      span = Span.byte(42, 10)
      label = Label.primary(span, "msg")

      assert Label.resolved_span(label) == span
    end

    test "converts tuple via Spannable protocol" do
      # 4-tuple is converted to Position span.
      label = Label.primary({5, 10, 5, 20}, "msg")

      resolved = Label.resolved_span(label)

      assert %Span.Position{
               start_line: 5,
               start_column: 10,
               end_line: 5,
               end_column: 20
             } = resolved
    end

    test "converts 2-tuple to Byte span" do
      # 2-tuple is interpreted as byte span.
      label = Label.primary({42, 10}, "msg")

      resolved = Label.resolved_span(label)

      assert %Span.Byte{start: 42, length: 10} = resolved
    end

    test "converts Range to Byte span" do
      label = Label.primary(10..20, "msg")

      resolved = Label.resolved_span(label)

      assert %Span.Byte{start: 10, length: 11} = resolved
    end
  end

  describe "labels with different span types" do
    test "works with Position span" do
      span = Span.position(5, 10)
      label = Label.primary(span, "msg")

      assert %Label{span: %Span.Position{}} = label
    end

    test "works with Byte span" do
      span = Span.byte(100, 5)
      label = Label.primary(span, "msg")

      assert %Label{span: %Span.Byte{}} = label
    end

    test "works with Search span" do
      span = Span.search(line: 5, pattern: "foo")
      label = Label.primary(span, "msg")

      assert %Label{span: %Span.Search{}} = label
    end
  end

  describe "property tests" do
    property "primary labels have priority :primary" do
      check all(
              line <- positive_integer(),
              col <- positive_integer(),
              msg <- one_of([constant(nil), string(:alphanumeric)])
            ) do
        span = Span.position(line, col)
        label = Label.primary(span, msg)

        assert label.priority == :primary
        assert Label.primary?(label)
        refute Label.secondary?(label)
      end
    end

    property "secondary labels have priority :secondary" do
      check all(
              line <- positive_integer(),
              col <- positive_integer(),
              msg <- one_of([constant(nil), string(:alphanumeric)])
            ) do
        span = Span.position(line, col)
        label = Label.secondary(span, msg)

        assert label.priority == :secondary
        assert Label.secondary?(label)
        refute Label.primary?(label)
      end
    end

    property "primary? and secondary? are mutually exclusive" do
      check all(
              line <- positive_integer(),
              col <- positive_integer(),
              priority <- member_of([:primary, :secondary])
            ) do
        span = Span.position(line, col)
        label = Label.new(span, priority: priority)

        assert Label.primary?(label) != Label.secondary?(label)
      end
    end

    property "resolved_span returns the original span for native span types" do
      check all(
              line <- positive_integer(),
              col <- positive_integer()
            ) do
        span = Span.position(line, col)
        label = Label.primary(span, "msg")

        assert Label.resolved_span(label) == span
      end
    end
  end
end
