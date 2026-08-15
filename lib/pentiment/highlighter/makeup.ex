defmodule Pentiment.Highlighter.Makeup do
  @moduledoc """
  Makeup-backed syntax highlighter.

  Active only when the optional `:makeup` lexer packages are present;
  add them to your own dependencies to enable highlighting:

      {:makeup_elixir, "~> 1.0"},
      {:makeup_erlang, "~> 1.0"}

  When the lexer for a language is not loaded, `highlight/2` returns
  `:error` and diagnostics render unhighlighted — there is no hard
  dependency on makeup.

  The full source is lexed in one pass (so heredocs, sigils, and other
  multi-line constructs style correctly across lines), then the token
  stream is split into per-line segments. Lexing runs once per source
  per `Pentiment.format/3` call.

  The palette is deliberately restrained — comments dim, literals in
  subtle colors, never red or yellow — so the formatter's label pointers
  remain the visually dominant element.
  """

  @behaviour Pentiment.Highlighter

  # Token-type color table, keyed by makeup's underscore-joined token
  # taxonomy. Lookup is longest-prefix: :comment_single falls back to
  # "comment", :string_regex to "string", while :string_symbol (atoms)
  # hits its exact entry before the "string" fallback. Types with no
  # entry (names, operators, punctuation) render unstyled.
  @token_colors %{
    "comment" => IO.ANSI.faint(),
    "string_symbol" => IO.ANSI.cyan(),
    "string" => IO.ANSI.green(),
    "keyword" => IO.ANSI.magenta(),
    "operator_word" => IO.ANSI.magenta(),
    "number" => IO.ANSI.cyan()
  }

  @impl true
  def highlight(content, language) when is_binary(content) do
    with {:ok, lexer} <- lexer_for(language),
         true <- Code.ensure_loaded?(lexer) and function_exported?(lexer, :lex, 1) do
      {:ok, content |> lexer.lex() |> line_map()}
    else
      _ -> :error
    end
  rescue
    # A lexer crash on pathological input must degrade to plain
    # rendering, never abort diagnostic formatting.
    _ -> :error
  end

  # The lexer modules are referenced only as atoms and called through a
  # variable, so pentiment compiles cleanly when makeup is absent and
  # picks the lexers up without recompilation when a consumer adds them.
  defp lexer_for(:elixir), do: {:ok, Makeup.Lexers.ElixirLexer}
  defp lexer_for(:erlang), do: {:ok, Makeup.Lexers.ErlangLexer}
  defp lexer_for(_language), do: :error

  # Folds the token stream into %{line_number => [segment]}. Token
  # values are chardata and may span lines; the token's style carries
  # across every embedded newline.
  defp line_map(tokens) do
    {map, line, current} =
      Enum.reduce(tokens, {%{}, 1, []}, fn {type, _meta, value}, acc ->
        # to_string([value]) is makeup's own chardata-to-binary
        # conversion; it handles values that are binaries, charlists,
        # or single codepoints alike.
        split_into_lines(to_string([value]), color_for(type), acc)
      end)

    Map.put(map, line, Enum.reverse(current))
  end

  defp split_into_lines(text, style, {map, line, current}) do
    [first | rest] = String.split(text, "\n")
    current = prepend_segment(current, style, first)

    Enum.reduce(rest, {map, line, current}, fn part, {map, line, current} ->
      {Map.put(map, line, Enum.reverse(current)), line + 1, prepend_segment([], style, part)}
    end)
  end

  defp prepend_segment(segments, _style, ""), do: segments
  defp prepend_segment(segments, style, text), do: [{style, text} | segments]

  defp color_for(type), do: lookup(Atom.to_string(type))

  defp lookup(key) when is_map_key(@token_colors, key), do: Map.fetch!(@token_colors, key)

  defp lookup(key) do
    case String.split(key, "_") do
      [_single_word] ->
        nil

      parts ->
        parts |> Enum.drop(-1) |> Enum.join("_") |> lookup()
    end
  end
end
