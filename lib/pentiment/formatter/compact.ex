defmodule Pentiment.Formatter.Compact do
  @moduledoc """
  Single-line diagnostic formatter.

  Produces concise output suitable for:
  - Macro error messages
  - Log output
  - Machine-parseable formats

  ## Example Output

      [E0001] Type mismatch (lib/my_app.ex:15:10)

  """

  alias Pentiment.{Diagnostic, Label, Span}

  @doc """
  Formats a diagnostic as a single line.

  ## Examples

      iex> Pentiment.Formatter.Compact.format(diagnostic)
      "[E0001] Type mismatch (lib/my_app.ex:15:10)"
  """
  @spec format(Diagnostic.t()) :: String.t()
  def format(diagnostic) do
    code = Diagnostic.code(diagnostic)
    message = Diagnostic.message(diagnostic)
    labels = Diagnostic.labels(diagnostic)

    code_str = if code, do: "[#{code}] ", else: ""
    location_str = format_location(labels, Diagnostic.source(diagnostic))

    if location_str do
      "#{code_str}#{message} (#{location_str})"
    else
      "#{code_str}#{message}"
    end
  end

  @doc """
  Formats multiple diagnostics, one per line.
  """
  @spec format_all([Diagnostic.t()]) :: String.t()
  def format_all(diagnostics) when is_list(diagnostics) do
    diagnostics
    |> Enum.map(&format/1)
    |> Enum.join("\n")
  end

  defp format_location([], _source), do: nil

  defp format_location([label | _], source) do
    case Label.resolved_span(label) do
      %Span.Position{start_line: line, start_column: col} ->
        format_location_string(source, line, col)

      %Span.Byte{start: offset} ->
        if source do
          "#{source}:byte #{offset}"
        else
          "byte #{offset}"
        end
    end
  end

  defp format_location_string(nil, line, col), do: "line #{line}:#{col}"
  defp format_location_string(file, line, col), do: "#{file}:#{line}:#{col}"
end
