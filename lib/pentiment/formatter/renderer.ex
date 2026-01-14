defmodule Pentiment.Formatter.Renderer do
  @moduledoc """
  Rich diagnostic formatter with source context and highlighting.

  This formatter produces compiler-style error output with:
  - Severity and error code header
  - Source location with unicode box-drawing frame
  - Highlighted source context with underlines and branching labels
  - Notes and help suggestions

  ## Example Output

      error[E0001]: Type mismatch
         ╭─[lib/my_app.ex:15:10]
         │
      14 │   add = fn x :: integer, y :: integer ->
      15 │     x + y + 1.5
         •             ─┬─
         •              ╰── expected `integer`, found `float`
         │
         ╰─────
            note: `+` with integer arguments returns integer
            help: consider using `trunc(1.5)`
  """

  alias Pentiment.{Diagnostic, Label, Source, Span}

  @type format_options :: [
          colors: boolean(),
          context_lines: non_neg_integer()
        ]

  @default_options [
    colors: true,
    context_lines: 2
  ]

  # ANSI color codes.
  @colors %{
    error: IO.ANSI.red(),
    warning: IO.ANSI.yellow(),
    info: IO.ANSI.cyan(),
    hint: IO.ANSI.blue(),
    note: IO.ANSI.cyan(),
    help: IO.ANSI.green(),
    bold: IO.ANSI.bright(),
    reset: IO.ANSI.reset(),
    dim: IO.ANSI.faint()
  }

  # Unicode box drawing characters.
  @box %{
    vertical: "│",
    horizontal: "─",
    top_left: "╭",
    bottom_left: "╰",
    dot: "•",
    tee_down: "┬"
  }

  # Maximum width for source lines.
  @max_source_width 80

  @doc """
  Formats a single diagnostic for display.

  ## Options

  - `:colors` - Whether to use ANSI colors (default: true, respects IO.ANSI.enabled?())
  - `:context_lines` - Number of lines of context around labels (default: 2)

  ## Sources

  Sources can be provided as:
  - A `Pentiment.Source` struct
  - A map of source names to content strings: `%{"file.ex" => "content..."}`
  - A map of source names to `Pentiment.Source` structs
  """
  @spec format(Diagnostic.t(), Source.t() | map(), format_options()) :: String.t()
  def format(diagnostic, sources, opts \\ []) do
    opts = Keyword.merge(@default_options, opts)
    use_colors = Keyword.get(opts, :colors, true) and IO.ANSI.enabled?()
    context_lines = Keyword.get(opts, :context_lines, 2)

    # Resolve source for this diagnostic.
    source = resolve_source(Diagnostic.source(diagnostic), sources)

    # Get labels and resolve any search spans against the source.
    labels =
      diagnostic
      |> Diagnostic.labels()
      |> resolve_search_spans(source)

    # Calculate line number width for consistent padding.
    line_num_width = calculate_line_num_width(labels, context_lines)

    [
      format_header(diagnostic, use_colors),
      format_location(labels, source, line_num_width, use_colors),
      format_source_context(labels, source, context_lines, line_num_width, use_colors),
      format_notes(diagnostic, line_num_width, use_colors),
      format_help(diagnostic, line_num_width, use_colors)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @doc """
  Formats multiple diagnostics for display.
  """
  @spec format_all([Diagnostic.t()], Source.t() | map(), format_options()) :: String.t()
  def format_all(diagnostics, sources, opts \\ []) when is_list(diagnostics) do
    diagnostics
    |> Enum.map(&format(&1, sources, opts))
    |> Enum.join("\n\n")
    |> then(fn formatted ->
      count = length(diagnostics)

      if count > 0 do
        summary = format_summary(diagnostics, opts)
        formatted <> "\n\n" <> summary
      else
        formatted
      end
    end)
  end

  # ============================================================================
  # Source Resolution
  # ============================================================================

  defp resolve_source(nil, _sources), do: nil

  defp resolve_source(source_name, %Source{} = source) do
    if Source.name(source) == source_name, do: source, else: nil
  end

  defp resolve_source(source_name, sources) when is_map(sources) do
    case Map.get(sources, source_name) do
      nil -> nil
      %Source{} = source -> source
      content when is_binary(content) -> Source.from_string(source_name, content)
    end
  end

  defp resolve_source(_source_name, _sources), do: nil

  # ============================================================================
  # Search Span Resolution
  # ============================================================================

  defp resolve_search_spans(labels, source) do
    Enum.map(labels, fn label ->
      case label.span do
        %Span.Search{} = search ->
          resolved = Span.Search.resolve(search, source)
          %{label | span: resolved}

        _ ->
          label
      end
    end)
  end

  # ============================================================================
  # Header Formatting
  # ============================================================================

  defp format_header(diagnostic, use_colors) do
    severity = Diagnostic.severity(diagnostic)
    code = Diagnostic.code(diagnostic)
    message = Diagnostic.message(diagnostic)

    severity_str = Atom.to_string(severity)
    formatted_message = bold_backtick_content(message, use_colors)

    code_part = if code, do: "[#{code}]", else: ""

    if use_colors do
      color = severity_color(severity)
      "#{color}#{@colors.bold}#{severity_str}#{code_part}#{@colors.reset}: #{formatted_message}"
    else
      "#{severity_str}#{code_part}: #{formatted_message}"
    end
  end

  # ============================================================================
  # Location Formatting
  # ============================================================================

  defp format_location([], _source, _line_num_width, _use_colors), do: nil

  defp format_location(labels, source, line_num_width, use_colors) do
    # Use the first label's location for the header.
    case get_first_label_location(labels) do
      nil ->
        nil

      {line, column} ->
        source_name = if source, do: Source.name(source), else: nil
        location_str = format_location_string(source_name, line, column)
        padding = String.duplicate(" ", line_num_width)

        if use_colors do
          "#{padding} #{@colors.dim}#{@box.top_left}#{@box.horizontal}[#{@colors.reset}#{location_str}#{@colors.dim}]#{@colors.reset}"
        else
          "#{padding} #{@box.top_left}#{@box.horizontal}[#{location_str}]"
        end
    end
  end

  defp get_first_label_location([label | _rest]) do
    case Label.resolved_span(label) do
      %Span.Position{start_line: line, start_column: col} -> {line, col}
      %Span.Byte{} -> nil
    end
  end

  defp format_location_string(nil, line, col), do: "line #{line}:#{col}"
  defp format_location_string(file, line, col), do: "#{file}:#{line}:#{col}"

  # ============================================================================
  # Source Context Formatting
  # ============================================================================

  defp format_source_context([], _source, _context_lines, _line_num_width, _use_colors), do: nil
  defp format_source_context(_labels, nil, _context_lines, _line_num_width, _use_colors), do: nil

  defp format_source_context(labels, source, context_lines, line_num_width, use_colors) do
    # Only handle Position spans for now.
    position_labels =
      labels
      |> Enum.filter(fn label ->
        case Label.resolved_span(label) do
          %Span.Position{} -> true
          _ -> false
        end
      end)

    if Enum.empty?(position_labels) do
      nil
    else
      format_multi_span_context(
        position_labels,
        source,
        context_lines,
        line_num_width,
        use_colors
      )
    end
  end

  defp format_multi_span_context(labels, source, context_lines, line_num_width, use_colors) do
    # Sort labels by line number.
    sorted_labels =
      labels
      |> Enum.sort_by(fn label ->
        %Span.Position{start_line: line} = Label.resolved_span(label)
        line
      end)

    # Calculate line range.
    span_lines =
      Enum.map(sorted_labels, fn label ->
        %Span.Position{start_line: line} = Label.resolved_span(label)
        line
      end)

    min_line = max(1, Enum.min(span_lines) - context_lines)
    max_line = Enum.max(span_lines) + context_lines

    padding = String.duplicate(" ", line_num_width)

    # Group labels by line.
    label_map =
      Enum.group_by(sorted_labels, fn label ->
        %Span.Position{start_line: line} = Label.resolved_span(label)
        line
      end)

    # Format each line in range.
    formatted_lines =
      min_line..max_line
      |> Enum.flat_map(fn line_num ->
        case Source.line(source, line_num) do
          nil ->
            []

          source_line ->
            case Map.get(label_map, line_num) do
              nil ->
                [format_context_line(line_num, source_line, line_num_width, use_colors)]

              labels_on_line ->
                format_labels_on_line(
                  labels_on_line,
                  source_line,
                  line_num,
                  line_num_width,
                  use_colors
                )
            end
        end
      end)

    if Enum.empty?(formatted_lines) do
      nil
    else
      separator =
        if use_colors do
          "#{padding} #{@colors.dim}#{@box.vertical}#{@colors.reset}"
        else
          "#{padding} #{@box.vertical}"
        end

      closing =
        if use_colors do
          "#{padding} #{@colors.dim}#{@box.bottom_left}#{String.duplicate(@box.horizontal, 5)}#{@colors.reset}"
        else
          "#{padding} #{@box.bottom_left}#{String.duplicate(@box.horizontal, 5)}"
        end

      ([separator] ++ formatted_lines ++ [separator, closing])
      |> Enum.join("\n")
    end
  end

  defp format_context_line(line_num, source_line, line_num_width, use_colors) do
    line_str = String.pad_leading(Integer.to_string(line_num), line_num_width)
    prefix_width = line_num_width + 3
    truncated_line = truncate_source_line(source_line, prefix_width)

    if use_colors do
      "#{@colors.dim}#{line_str} #{@box.vertical}#{@colors.reset} #{truncated_line}"
    else
      "#{line_str} #{@box.vertical} #{truncated_line}"
    end
  end

  defp format_labels_on_line(labels, source_line, line_num, line_num_width, use_colors) do
    padding = String.duplicate(" ", line_num_width)
    line_str = String.pad_leading(Integer.to_string(line_num), line_num_width)
    prefix_width = line_num_width + 3
    truncated_line = truncate_source_line(source_line, prefix_width)

    source =
      if use_colors do
        "#{@colors.dim}#{line_str}#{@colors.reset} #{@colors.dim}#{@box.vertical}#{@colors.reset} #{truncated_line}"
      else
        "#{line_str} #{@box.vertical} #{truncated_line}"
      end

    pointer_lines =
      labels
      |> Enum.flat_map(fn label ->
        format_label_pointer(label, source_line, padding, use_colors)
      end)

    [source | pointer_lines]
  end

  defp format_label_pointer(label, source_line, padding, use_colors) do
    span = Label.resolved_span(label)
    message = label.message
    priority = label.priority

    col = span.start_column || 1

    # Calculate pointer width.
    pointer_width = estimate_span_width(span, source_line, col)

    # Build underline with tee at center.
    {underline, tee_position} = build_underline_with_tee(pointer_width)

    pointer_padding = String.duplicate(" ", max(0, col - 1))
    branch_padding = String.duplicate(" ", max(0, col - 1 + tee_position))

    label_text = message || ""
    span_color = if use_colors, do: priority_color(priority), else: ""

    if use_colors do
      underline_line =
        "#{padding} #{@colors.dim}#{@box.dot}#{@colors.reset} #{pointer_padding}#{span_color}#{underline}#{@colors.reset}"

      label_line =
        "#{padding} #{@colors.dim}#{@box.dot}#{@colors.reset} #{branch_padding}#{span_color}#{@box.bottom_left}#{@box.horizontal}#{@box.horizontal} #{label_text}#{@colors.reset}"

      [underline_line, label_line]
    else
      underline_line = "#{padding} #{@box.dot} #{pointer_padding}#{underline}"

      label_line =
        "#{padding} #{@box.dot} #{branch_padding}#{@box.bottom_left}#{@box.horizontal}#{@box.horizontal} #{label_text}"

      [underline_line, label_line]
    end
  end

  defp estimate_span_width(
         %Span.Position{start_column: start_col, end_column: end_col},
         _source_line,
         _col
       )
       when is_integer(end_col) and end_col > start_col do
    end_col - start_col
  end

  defp estimate_span_width(_span, _source_line, _col) do
    # For point spans without end_column, default to 1 character.
    # Callers who want wider spans should provide explicit end_column.
    1
  end

  defp build_underline_with_tee(width) when width <= 1 do
    {@box.tee_down, 0}
  end

  defp build_underline_with_tee(width) do
    center = div(width - 1, 2)
    left_dashes = String.duplicate(@box.horizontal, center)
    right_dashes = String.duplicate(@box.horizontal, width - center - 1)
    {left_dashes <> @box.tee_down <> right_dashes, center}
  end

  # ============================================================================
  # Notes and Help Formatting
  # ============================================================================

  defp format_notes(diagnostic, line_num_width, use_colors) do
    notes = Diagnostic.notes(diagnostic)

    if Enum.empty?(notes) do
      nil
    else
      notes
      |> Enum.map(fn note -> format_note(note, line_num_width, use_colors) end)
      |> Enum.join("\n")
    end
  end

  defp format_note(note, line_num_width, use_colors) do
    formatted_note = bold_backtick_content(note, use_colors)
    padding = String.duplicate(" ", line_num_width + 3)

    if use_colors do
      "#{padding}#{@colors.note}note#{@colors.reset}: #{formatted_note}"
    else
      "#{padding}note: #{formatted_note}"
    end
  end

  defp format_help(diagnostic, line_num_width, use_colors) do
    help = Diagnostic.help(diagnostic)

    if Enum.empty?(help) do
      nil
    else
      help
      |> Enum.map(fn h -> format_help_item(h, line_num_width, use_colors) end)
      |> Enum.join("\n")
    end
  end

  defp format_help_item(help, line_num_width, use_colors) do
    formatted_help = bold_backtick_content(help, use_colors)
    padding = String.duplicate(" ", line_num_width + 3)

    if use_colors do
      "#{padding}#{@colors.help}help#{@colors.reset}: #{formatted_help}"
    else
      "#{padding}help: #{formatted_help}"
    end
  end

  # ============================================================================
  # Summary Formatting
  # ============================================================================

  defp format_summary(diagnostics, opts) do
    use_colors = Keyword.get(opts, :colors, true) and IO.ANSI.enabled?()

    error_count = Enum.count(diagnostics, fn d -> Diagnostic.severity(d) == :error end)
    warning_count = Enum.count(diagnostics, fn d -> Diagnostic.severity(d) == :warning end)

    parts = []

    parts =
      if error_count > 0, do: parts ++ ["#{error_count} error#{plural(error_count)}"], else: parts

    parts =
      if warning_count > 0,
        do: parts ++ ["#{warning_count} warning#{plural(warning_count)}"],
        else: parts

    summary_text = Enum.join(parts, ", ")

    if use_colors do
      "#{@colors.bold}#{summary_text} emitted#{@colors.reset}"
    else
      "#{summary_text} emitted"
    end
  end

  defp plural(1), do: ""
  defp plural(_), do: "s"

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp calculate_line_num_width([], _context_lines), do: 1

  defp calculate_line_num_width(labels, context_lines) do
    max_line =
      labels
      |> Enum.map(fn label ->
        case Label.resolved_span(label) do
          %Span.Position{start_line: line} -> line + context_lines
          _ -> 1
        end
      end)
      |> Enum.max(fn -> 1 end)

    String.length(Integer.to_string(max_line))
  end

  defp severity_color(:error), do: @colors.error
  defp severity_color(:warning), do: @colors.warning
  defp severity_color(:info), do: @colors.info
  defp severity_color(:hint), do: @colors.hint

  defp priority_color(:primary), do: @colors.error
  defp priority_color(:secondary), do: @colors.warning

  defp truncate_source_line(line, prefix_width) do
    max_content_width = max(@max_source_width - prefix_width, 20)

    if String.length(line) > max_content_width do
      String.slice(line, 0, max_content_width - 1) <> "…"
    else
      line
    end
  end

  defp bold_backtick_content(text, false), do: text

  defp bold_backtick_content(text, true) do
    Regex.replace(~r/`([^`]+)`/, text, "`#{@colors.bold}\\1#{@colors.reset}`")
  end
end
