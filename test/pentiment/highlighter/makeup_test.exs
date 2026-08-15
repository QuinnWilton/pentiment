defmodule Pentiment.Highlighter.MakeupTest do
  use ExUnit.Case, async: true

  alias Pentiment.Highlighter

  @moduletag :requires_makeup

  @elixir_source """
  defmodule Sample do
    @moduledoc \"\"\"
    A sample module with a heredoc
    spanning several lines.
    \"\"\"

    # A comment with unicode: héllo ✓
    def greet(name) do
      ~s(sigil text) <> "hello " <> name <> to_string(:atom) <> "42"
    end
  end
  """

  @erlang_source """
  -module(sample).
  -export([f/1]).

  %% A comment.
  f(X) ->
      {ok, X + 42}.
  """

  defp roundtrip(content, language) do
    assert {:ok, line_map} = Highlighter.Makeup.highlight(content, language)

    lines = String.split(content, "\n")

    reconstructed =
      Enum.map_join(1..length(lines), "\n", fn line_num ->
        line_map
        |> Map.get(line_num, [])
        |> Enum.map_join(fn {_style, text} -> text end)
      end)

    assert reconstructed == content
    line_map
  end

  describe "highlight/2 round-trip" do
    test "joining segment texts reproduces the elixir source exactly" do
      roundtrip(@elixir_source, :elixir)
    end

    test "joining segment texts reproduces the erlang source exactly" do
      roundtrip(@erlang_source, :erlang)
    end

    test "round-trips source without a trailing newline" do
      roundtrip("def f, do: :ok", :elixir)
    end

    test "round-trips empty content" do
      roundtrip("", :elixir)
    end
  end

  describe "multi-line constructs" do
    test "a line strictly inside a heredoc is styled as a string" do
      line_map = roundtrip(@elixir_source, :elixir)

      # Line 3 of the source is heredoc-interior text.
      assert [{style, "  A sample module with a heredoc"}] = line_map[3]
      assert style == IO.ANSI.green()
    end
  end

  describe "palette" do
    test "comments are faint" do
      line_map = roundtrip("# just a comment", :elixir)

      assert [{style, "# just a comment"}] = line_map[1]
      assert style == IO.ANSI.faint()
    end

    test "atoms are cyan" do
      line_map = roundtrip(":ok", :elixir)

      assert [{style, ":ok"}] = line_map[1]
      assert style == IO.ANSI.cyan()
    end

    test "def is magenta" do
      line_map = roundtrip("def f, do: 1", :elixir)

      assert {style, "def"} = List.first(line_map[1])
      assert style == IO.ANSI.magenta()
    end

    test "numbers are cyan and plain names are unstyled" do
      line_map = roundtrip("x = 42", :elixir)

      assert [{nil, "x"}, {nil, " "}, {nil, "="}, {nil, " "}, {number_style, "42"}] =
               line_map[1]

      assert number_style == IO.ANSI.cyan()
    end
  end

  describe "unsupported languages" do
    test "returns :error for an unknown language" do
      assert Highlighter.Makeup.highlight("puts 'hi'", :ruby) == :error
    end

    test "returns :error for nil language" do
      assert Highlighter.Makeup.highlight("text", nil) == :error
    end
  end
end
