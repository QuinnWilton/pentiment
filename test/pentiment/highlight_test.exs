# Stub highlighters for exercising the seam without makeup.
defmodule Pentiment.HighlightTest.CyanLineHighlighter do
  @moduledoc false
  @behaviour Pentiment.Highlighter

  @impl true
  def highlight(content, _language) do
    line_map =
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Map.new(fn
        {"", line_num} -> {line_num, []}
        {line, line_num} -> {line_num, [{IO.ANSI.cyan(), line}]}
      end)

    {:ok, line_map}
  end
end

defmodule Pentiment.HighlightTest.FailingHighlighter do
  @moduledoc false
  @behaviour Pentiment.Highlighter

  @impl true
  def highlight(_content, _language), do: :error
end

defmodule Pentiment.HighlightTest.MisalignedHighlighter do
  @moduledoc false
  @behaviour Pentiment.Highlighter

  # Violates the segment contract: claims every line reads "WRONG".
  @impl true
  def highlight(content, _language) do
    line_map =
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Map.new(fn {_line, line_num} -> {line_num, [{IO.ANSI.cyan(), "WRONG"}]} end)

    {:ok, line_map}
  end
end

defmodule Pentiment.HighlightTest do
  # async: false — this module toggles the global :ansi_enabled setting.
  # ExUnit runs sync modules after all async ones, so the existing suite
  # (which passes colors: false everywhere) can never observe the toggle.
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Pentiment.HighlightTest.{CyanLineHighlighter, FailingHighlighter, MisalignedHighlighter}
  alias Pentiment.{Label, Report, Source, Span}

  setup do
    previous = Application.get_env(:elixir, :ansi_enabled)
    Application.put_env(:elixir, :ansi_enabled, true)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:elixir, :ansi_enabled)
      else
        Application.put_env(:elixir, :ansi_enabled, previous)
      end
    end)

    :ok
  end

  defp strip_ansi(string), do: Regex.replace(~r/\e\[[0-9;]*m/, string, "")

  # A realistic 20-line Elixir module: heredoc, comment, sigil, atoms, and
  # one line wider than the 80-column truncation threshold (line 11).
  @elixir_content """
  defmodule Sample.Worker do
    @moduledoc \"\"\"
    A worker that greets people
    in several languages.
    \"\"\"

    # Greeting prefix used everywhere.
    @prefix "Hello"

    def greet(name) when is_binary(name) do
      message = "greetings and welcome to the sample worker module with quite a long line"
      {:ok, message}
    end

    def farewell(name) do
      ~s(Goodbye) <> name
    end

    defp helper, do: :ok
  end
  """

  # Mirrors the shapes of the byte-identity golden: a bracket label, an
  # inline secondary inside it, a distant primary behind a gap marker,
  # plus a note and help.
  defp representative_report do
    Report.error("Representative highlighted diagnostic")
    |> Report.with_code("E200")
    |> Report.with_source("lib/sample/worker.ex")
    |> Report.with_label(Label.bracket(Span.position(10, 1, 13, 3), "function under scrutiny"))
    |> Report.with_label(Label.secondary(Span.position(11, 5, 11, 11), "this binding"))
    |> Report.with_label(Label.primary(Span.position(19, 20, 19, 22), "distant evidence"))
    |> Report.with_note("a note about the function")
    |> Report.with_help("a suggestion for the fix")
  end

  defp elixir_source, do: Source.from_string("lib/sample/worker.ex", @elixir_content)

  describe "alignment invariant" do
    @tag :requires_makeup
    test "stripping ANSI from highlighted output equals the plain output" do
      report = representative_report()
      source = elixir_source()

      colored = Pentiment.format(report, source, colors: true)
      plain = Pentiment.format(report, source, colors: false)

      # Highlighting actually happened (not a vacuous pass).
      assert colored =~ IO.ANSI.magenta()
      assert colored =~ IO.ANSI.green()

      assert strip_ansi(colored) == plain
    end

    @tag :requires_makeup
    property "invariant holds for arbitrary label positions" do
      line_count = @elixir_content |> String.split("\n") |> length()
      source = elixir_source()

      check all(
              labels <-
                list_of(
                  {integer(1..line_count), integer(1..10), integer(1..8),
                   member_of([:primary, :secondary])},
                  min_length: 1,
                  max_length: 3
                )
            ) do
        report =
          Enum.reduce(
            labels,
            Report.error("prop") |> Report.with_source("lib/sample/worker.ex"),
            fn
              {line, col, width, priority}, report ->
                span = Span.position(line, col, line, col + width)

                label =
                  case priority do
                    :primary -> Label.primary(span, "p")
                    :secondary -> Label.secondary(span, "s")
                  end

                Report.with_label(report, label)
            end
          )

        colored = Pentiment.format(report, source, colors: true)
        plain = Pentiment.format(report, source, colors: false)

        assert strip_ansi(colored) == plain
      end
    end
  end

  describe "multi-line constructs" do
    @tag :requires_makeup
    test "a context line inside a heredoc is styled as a string" do
      # Label on line 3, which is heredoc-interior text.
      report =
        Report.error("heredoc")
        |> Report.with_source("lib/sample/worker.ex")
        |> Report.with_label(Label.primary(Span.position(3, 3, 3, 10), "here"))

      colored = Pentiment.format(report, elixir_source(), colors: true)

      # The heredoc token includes the interior line's leading indentation.
      assert colored =~ "#{IO.ANSI.green()}  A worker that greets people#{IO.ANSI.reset()}"
    end
  end

  describe "truncation" do
    @tag :requires_makeup
    test "over-wide highlighted lines truncate identically to plain ones" do
      # Line 11 is wider than the 80-column threshold.
      report =
        Report.error("wide")
        |> Report.with_source("lib/sample/worker.ex")
        |> Report.with_label(Label.primary(Span.position(11, 5, 11, 11), "here"))

      colored = Pentiment.format(report, elixir_source(), colors: true)
      plain = Pentiment.format(report, elixir_source(), colors: false)

      assert strip_ansi(colored) == plain
      assert plain =~ "…"
    end
  end

  describe "colored golden" do
    @tag :requires_makeup
    test "renders exact escapes for a tiny diagnostic" do
      content = "defmodule Tiny do\n  :ok\nend"

      report =
        Report.error("Tiny diagnostic")
        |> Report.with_code("E001")
        |> Report.with_source("tiny.ex")
        |> Report.with_label(Label.primary(Span.position(2, 3, 2, 5), "an atom"))

      result = Pentiment.format(report, Source.from_string("tiny.ex", content), colors: true)

      red = IO.ANSI.red()
      cyan = IO.ANSI.cyan()
      magenta = IO.ANSI.magenta()
      bold = IO.ANSI.bright()
      dim = IO.ANSI.faint()
      reset = IO.ANSI.reset()

      # Built from a line list, mirroring the plain golden. Pins the exact
      # interleaving of frame decoration, palette styles, and resets.
      expected =
        Enum.join(
          [
            "#{red}#{bold}error[E001]#{reset}: Tiny diagnostic",
            "  #{dim}╭─[#{reset}tiny.ex:2:3#{dim}]#{reset}",
            "  #{dim}│#{reset}",
            "#{dim}1 │#{reset} #{magenta}defmodule#{reset} Tiny #{magenta}do#{reset}",
            "#{dim}2#{reset} #{dim}│#{reset}   #{cyan}:ok#{reset}",
            "  #{dim}•#{reset}   #{red}┬─#{reset}",
            "  #{dim}•#{reset}   #{red}╰── an atom#{reset}",
            "#{dim}3 │#{reset} #{magenta}end#{reset}",
            "  #{dim}│#{reset}",
            "  #{dim}╰─────#{reset}"
          ],
          "\n"
        )

      assert result == expected

      # The same call without makeup styling: strip and compare to plain.
      assert strip_ansi(result) ==
               Pentiment.format(report, Source.from_string("tiny.ex", content), colors: false)
    end
  end

  describe "fallbacks" do
    test "syntax: false matches a highlighter that declines" do
      report = representative_report()
      source = elixir_source()

      disabled = Pentiment.format(report, source, colors: true, syntax: false)
      declined = Pentiment.format(report, source, colors: true, highlighter: FailingHighlighter)

      assert disabled == declined
      refute strip_ansi(disabled) =~ "\e["
    end

    test "unknown language renders as if syntax was disabled" do
      # "no-extension" infers no language, so the highlighter is never asked.
      source = Source.from_string("no-extension", @elixir_content)

      report =
        Report.error("unknown language")
        |> Report.with_source("no-extension")
        |> Report.with_label(Label.primary(Span.position(10, 1, 10, 3), "here"))

      auto = Pentiment.format(report, source, colors: true)
      disabled = Pentiment.format(report, source, colors: true, syntax: false)

      assert auto == disabled
    end

    test "a contract-violating highlighter falls back to plain lines" do
      report = representative_report()
      source = elixir_source()

      misaligned =
        Pentiment.format(report, source, colors: true, highlighter: MisalignedHighlighter)

      disabled = Pentiment.format(report, source, colors: true, syntax: false)

      # Segments disagreeing with the raw line are discarded wholesale.
      refute misaligned =~ "WRONG"
      assert misaligned == disabled
    end
  end

  describe "custom highlighter" do
    test "the :highlighter option substitutes the default" do
      report = representative_report()
      source = elixir_source()

      colored = Pentiment.format(report, source, colors: true, highlighter: CyanLineHighlighter)
      plain = Pentiment.format(report, source, colors: false)

      assert colored =~ IO.ANSI.cyan()
      assert strip_ansi(colored) == plain
    end
  end

  describe "colors: false stays the single plain switch" do
    test "syntax cannot activate highlighting when colors are off" do
      report = representative_report()
      source = elixir_source()

      assert Pentiment.format(report, source, colors: false, syntax: true) ==
               Pentiment.format(report, source, colors: false)

      assert Pentiment.format(report, source, colors: false, highlighter: CyanLineHighlighter) ==
               Pentiment.format(report, source, colors: false)
    end
  end
end
