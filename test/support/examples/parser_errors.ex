defmodule Pentiment.Examples.ParserErrors do
  @moduledoc """
  Example: Rich error messages from NimbleParsec parsers.

  This example demonstrates how to use Pentiment with NimbleParsec to provide
  clear, helpful error messages for parser failures. Key patterns shown:

  - Using `pre_traverse` to capture position info during parsing
  - Converting nimble_parsec positions to Pentiment spans
  - Analyzing remaining input for contextual error messages

  **Requires optional dependency:** `{:nimble_parsec, "~> 1.0"}`

  ## Usage

      case Pentiment.Examples.ParserErrors.parse("expr.lang", "let x = 10 + ") do
        {:ok, ast} -> evaluate(ast)
        {:error, formatted} -> IO.puts(formatted)
      end

  ## Error Output

  Trailing operator with missing operand:

      error[PARSE001]: Unexpected token
         ╭─[expr.lang:1:12]
         │
       1 │ let x = 10 +
         •            ┬
         •            ╰── unexpected `+`
         │
         ╰─
            note: operator requires a right-hand operand

  Unexpected token after valid expression:

      error[PARSE001]: Unexpected token
         ╭─[expr.lang:1:12]
         │
       1 │ let x = 10 extra
         •            ┬
         •            ╰── unexpected `e`
         │
         ╰─
  """

  import NimbleParsec

  # Define a simple expression parser.
  # This is a minimal example - real parsers would be more comprehensive.

  whitespace = ascii_string([?\s, ?\t], min: 1) |> ignore()

  identifier =
    ascii_char([?a..?z, ?_])
    |> repeat(ascii_char([?a..?z, ?A..?Z, ?0..?9, ?_]))
    |> reduce({List, :to_string, []})
    |> unwrap_and_tag(:ident)

  integer_literal =
    optional(ascii_char([?-]))
    |> ascii_string([?0..?9], min: 1)
    |> reduce({__MODULE__, :parse_integer, []})
    |> unwrap_and_tag(:int)

  operator =
    choice([
      string("+") |> replace(:add),
      string("-") |> replace(:sub),
      string("*") |> replace(:mul),
      string("/") |> replace(:div)
    ])
    |> unwrap_and_tag(:op)

  # Simple: let <ident> = <expr>
  let_keyword = string("let") |> replace(:let)

  equals = string("=") |> replace(:equals)

  # A primary expression is an integer or identifier.
  primary_expr =
    choice([
      integer_literal,
      identifier
    ])

  # An expression can be a primary, optionally followed by operator and another expression.
  # This handles: 10, 10 + 5, 10 * 5 + 2, etc.
  expr =
    primary_expr
    |> repeat(
      ignore(optional(whitespace))
      |> concat(operator)
      |> ignore(optional(whitespace))
      |> concat(primary_expr)
    )
    |> tag(:expr)

  # A simple let binding: let x = 10 + 5
  let_binding =
    let_keyword
    |> ignore(optional(whitespace))
    |> concat(identifier)
    |> ignore(optional(whitespace))
    |> concat(equals)
    |> ignore(optional(whitespace))
    |> concat(expr)
    |> tag(:let_binding)

  defparsec(:parse_let, let_binding)

  @doc false
  def parse_integer(chars) do
    chars
    |> IO.iodata_to_binary()
    |> String.to_integer()
  end

  @doc """
  Parses input with rich error reporting.

  Returns `{:ok, ast}` on success, or `{:error, formatted_message}` on failure.
  """
  @spec parse(String.t(), String.t()) :: {:ok, term()} | {:error, String.t()}
  def parse(source_name, input) do
    source = Pentiment.Source.from_string(source_name, input)

    case parse_let(input) do
      {:ok, tokens, "", _, _, _} ->
        {:ok, tokens}

      {:ok, _tokens, rest, _, {line, line_offset}, byte_offset} ->
        # Partial parse - unexpected content remains.
        # Skip leading whitespace to find the actual unexpected token.
        whitespace_len = String.length(rest) - String.length(String.trim_leading(rest))
        col = byte_offset - line_offset + 1 + whitespace_len
        {unexpected, hint} = analyze_unexpected(rest)

        span = Pentiment.Span.position(line, col, line, col + String.length(unexpected))

        report =
          Pentiment.Report.error("Unexpected token")
          |> Pentiment.Report.with_code("PARSE001")
          |> Pentiment.Report.with_source(source_name)
          |> Pentiment.Report.with_label(
            Pentiment.Label.primary(span, "unexpected `#{unexpected}`")
          )
          |> maybe_add_note(hint)

        {:error, Pentiment.format(report, source, colors: false)}

      {:error, message, _rest, _, {line, line_offset}, byte_offset} ->
        col = byte_offset - line_offset + 1
        span = Pentiment.Span.position(line, col)

        report =
          Pentiment.Report.error(message)
          |> Pentiment.Report.with_code("PARSE002")
          |> Pentiment.Report.with_source(source_name)
          |> Pentiment.Report.with_label(Pentiment.Label.primary(span, "parse error here"))

        {:error, Pentiment.format(report, source, colors: false)}
    end
  end

  defp analyze_unexpected(rest) do
    # Skip leading whitespace to find the actual unexpected token.
    trimmed = String.trim_leading(rest)

    case trimmed do
      "+" <> _ -> {"+", "operator requires a right-hand operand"}
      "-" <> _ -> {"-", "operator requires a right-hand operand"}
      "*" <> _ -> {"*", "operator requires a right-hand operand"}
      "/" <> _ -> {"/", "operator requires a right-hand operand"}
      ")" <> _ -> {")", "unmatched closing parenthesis"}
      <<c, _::binary>> -> {<<c>>, nil}
      "" -> {"end of input", "expression is incomplete"}
    end
  end

  defp maybe_add_note(report, nil), do: report
  defp maybe_add_note(report, note), do: Pentiment.Report.with_note(report, note)
end
