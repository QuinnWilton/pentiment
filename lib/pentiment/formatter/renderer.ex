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

  ## Multi-file Diagnostics

  Labels carrying their own `:source` render as continuation frames inside
  the same diagnostic: the report's own file opens the frame with `╭─[...]`,
  each additional file is introduced with `├─[file:line:col]` and rendered
  against its own source, and a single `╰─────` closes the frame. Groups
  whose source is missing from the provided sources render header-only.
  """

  alias Pentiment.{Diagnostic, Label, Source, Span}

  @type format_options :: [
          colors: boolean(),
          context_lines: non_neg_integer(),
          syntax: :auto | boolean(),
          highlighter: module()
        ]

  @default_options [
    colors: true,
    context_lines: 2,
    syntax: :auto
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
    tee_left: "├",
    dot: "•",
    tee_down: "┬",
    bracket_bar: "│"
  }

  # Maximum width for source lines.
  @max_source_width 80

  @doc """
  Formats a single diagnostic for display.

  ## Options

  - `:colors` - Whether to use ANSI colors (default: true, respects IO.ANSI.enabled?())
  - `:context_lines` - Number of lines of context around labels (default: 2)
  - `:syntax` - Whether to syntax-highlight source context lines (default:
    `:auto`). `:auto` highlights when colors are active, a highlighter is
    available, and the source's language is known; `false` disables.
    Highlighting is strictly subordinate to `:colors` — `colors: false`
    always yields plain text.
  - `:highlighter` - Module implementing `Pentiment.Highlighter`
    (default: `Pentiment.Highlighter.Makeup`)

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

    report_source = Diagnostic.source(diagnostic)
    highlighter = active_highlighter(opts, use_colors)

    # Group labels by their effective source (label source, falling back to
    # the report's source), then resolve each group's source and deferred
    # spans (Search, Byte) against that group's own file. Each group also
    # carries its highlight line map (nil when highlighting is inactive),
    # computed here so every source is lexed at most once per format call.
    groups =
      diagnostic
      |> Diagnostic.labels()
      |> group_labels_by_source(report_source)
      |> Enum.map(fn {name, labels} ->
        source = resolve_source(name, sources)

        {name, source, resolve_deferred_spans(labels, source),
         highlight_source(source, highlighter)}
      end)

    # Line number width is global across all groups so the frame, notes, and
    # help all share one gutter alignment.
    all_labels = Enum.flat_map(groups, fn {_name, _source, labels, _highlights} -> labels end)
    line_num_width = calculate_line_num_width(all_labels, context_lines)

    [
      format_header(diagnostic, use_colors),
      format_source_groups(groups, context_lines, line_num_width, use_colors),
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
    |> Enum.map_join("\n\n", &format(&1, sources, opts))
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
  # Syntax Highlighting
  # ============================================================================

  # Picks the highlighter module for this format call, or nil when
  # highlighting is inactive. `syntax: :auto` (the default) highlights only
  # when the colors gate is already open — `colors: false` remains the
  # single plain-text switch, and no additional TTY probing happens here.
  # `syntax: false` disables highlighting outright (`true` behaves as
  # `:auto`).
  defp active_highlighter(opts, use_colors) do
    cond do
      not use_colors -> nil
      Keyword.get(opts, :syntax, :auto) == false -> nil
      true -> Keyword.get(opts, :highlighter, Pentiment.Highlighter.Makeup)
    end
  end

  # Lexes a source into a per-line segment map, or nil when highlighting
  # does not apply: no highlighter active, no content to lex, unknown
  # language, or the highlighter declined.
  defp highlight_source(%Source{content: content, language: language}, highlighter)
       when is_binary(content) and not is_nil(language) and not is_nil(highlighter) do
    case highlighter.highlight(content, language) do
      {:ok, line_map} -> line_map
      :error -> nil
    end
  end

  defp highlight_source(_source, _highlighter), do: nil

  # ============================================================================
  # Deferred Span Resolution
  # ============================================================================

  defp resolve_deferred_spans(labels, source) do
    Enum.map(labels, fn label ->
      resolved_span =
        case label.span do
          %Span.Search{} = search ->
            Span.Search.resolve(search, source)

          %Span.Byte{} = byte ->
            Span.Byte.resolve(byte, source)

          other ->
            other
        end

      %{label | span: resolved_span}
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
  # Source Grouping
  # ============================================================================

  # Groups labels by their effective source name (`label.source`, falling back
  # to the report's source), preserving diagnostic order within each group and
  # ordering groups by first appearance — except the report-source group, which
  # always leads because it owns the `╭─` frame header. A label whose `:source`
  # explicitly equals the report's source lands in the lead group, identical to
  # leaving it nil.
  defp group_labels_by_source(labels, report_source) do
    {order, grouped} =
      Enum.reduce(labels, {[], %{}}, fn label, {order, grouped} ->
        key = label.source || report_source

        case grouped do
          %{^key => group} -> {order, %{grouped | key => [label | group]}}
          _ -> {[key | order], Map.put(grouped, key, [label])}
        end
      end)

    order
    |> Enum.reverse()
    |> Enum.map(fn key -> {key, Enum.reverse(grouped[key])} end)
    |> Enum.sort_by(fn {key, _labels} -> if key == report_source, do: 0, else: 1 end)
  end

  # ============================================================================
  # Frame Assembly
  # ============================================================================

  # Renders all source groups as one frame: the lead group opens with
  # `╭─[...]`, continuation groups are introduced with `├─[...]`, and a single
  # `╰─────` closes the frame. A group whose source could not be resolved
  # renders header-only — the header already carries file, line, and column.
  defp format_source_groups([], _context_lines, _line_num_width, _use_colors), do: nil

  defp format_source_groups(groups, context_lines, line_num_width, use_colors) do
    padding = String.duplicate(" ", line_num_width)

    sections =
      groups
      |> Enum.with_index()
      |> Enum.map(fn {{name, source, labels, highlights}, index} ->
        style = if index == 0, do: :open, else: :continue

        # The lead group keeps the historical header semantics (file name from
        # the resolved source, `line X:Y` fallback when unresolved).
        # Continuation groups always show their group name: it is the only
        # place their file is identified, resolved source or not.
        display_name =
          case style do
            :open -> if source, do: Source.name(source), else: nil
            :continue -> name
          end

        header = format_frame_header(style, display_name, labels, line_num_width, use_colors)

        body =
          format_source_context(
            labels,
            source,
            context_lines,
            line_num_width,
            use_colors,
            highlights
          )

        {header, body}
      end)

    any_header? = Enum.any?(sections, fn {header, _body} -> header != nil end)
    any_body? = Enum.any?(sections, fn {_header, body} -> body != nil end)

    if any_header? or any_body? do
      separator = format_separator(padding, use_colors)

      lines =
        Enum.flat_map(sections, fn
          {nil, nil} -> []
          {header, nil} -> [header]
          {nil, body} -> [separator, body, separator]
          {header, body} -> [header, separator, body, separator]
        end)

      # A single header-only group stays open-ended (historical behavior);
      # anything more substantial closes the frame so a trailing continuation
      # header never dangles.
      closing =
        if any_body? or length(groups) > 1 do
          [format_frame_close(padding, use_colors)]
        else
          []
        end

      Enum.join(lines ++ closing, "\n")
    else
      nil
    end
  end

  defp format_frame_header(_style, _display_name, [], _line_num_width, _use_colors), do: nil

  defp format_frame_header(style, display_name, labels, line_num_width, use_colors) do
    # Use the group's first label location for the header.
    case get_first_label_location(labels) do
      nil ->
        nil

      {line, column} ->
        location_str = format_location_string(display_name, line, column)
        padding = String.duplicate(" ", line_num_width)

        corner =
          case style do
            :open -> @box.top_left
            :continue -> @box.tee_left
          end

        if use_colors do
          "#{padding} #{@colors.dim}#{corner}#{@box.horizontal}[#{@colors.reset}#{location_str}#{@colors.dim}]#{@colors.reset}"
        else
          "#{padding} #{corner}#{@box.horizontal}[#{location_str}]"
        end
    end
  end

  defp format_separator(padding, use_colors) do
    if use_colors do
      "#{padding} #{@colors.dim}#{@box.vertical}#{@colors.reset}"
    else
      "#{padding} #{@box.vertical}"
    end
  end

  defp format_frame_close(padding, use_colors) do
    if use_colors do
      "#{padding} #{@colors.dim}#{@box.bottom_left}#{String.duplicate(@box.horizontal, 5)}#{@colors.reset}"
    else
      "#{padding} #{@box.bottom_left}#{String.duplicate(@box.horizontal, 5)}"
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

  defp format_source_context([], _source, _context_lines, _line_num_width, _use_colors, _hl),
    do: nil

  defp format_source_context(_labels, nil, _context_lines, _line_num_width, _use_colors, _hl),
    do: nil

  defp format_source_context(
         labels,
         source,
         context_lines,
         line_num_width,
         use_colors,
         highlights
       ) do
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
        use_colors,
        highlights
      )
    end
  end

  defp format_multi_span_context(
         labels,
         source,
         context_lines,
         line_num_width,
         use_colors,
         highlights
       ) do
    # Sort labels by line number.
    sorted_labels =
      labels
      |> Enum.sort_by(fn label ->
        %Span.Position{start_line: line} = Label.resolved_span(label)
        line
      end)

    # Partition into bracket vs inline labels.
    {bracket_labels, inline_labels} = Enum.split_with(sorted_labels, &Label.bracket?/1)

    # Group inline labels by their start line.
    label_map =
      Enum.group_by(inline_labels, fn label ->
        %Span.Position{start_line: line} = Label.resolved_span(label)
        line
      end)

    # Compute bracket active-lines map and column count.
    bracket_map = compute_bracket_map(bracket_labels)
    bracket_col_count = compute_bracket_col_count(bracket_map)

    # Compute visible ranges from inline labels.
    inline_span_lines =
      Enum.map(inline_labels, fn label ->
        %Span.Position{start_line: line} = Label.resolved_span(label)
        line
      end)

    inline_ranges = compute_display_ranges(inline_span_lines, context_lines)

    # Compute visible ranges from bracket labels (full line range, no elision within).
    bracket_ranges =
      Enum.map(bracket_labels, fn label ->
        span = Label.resolved_span(label)
        end_line = span.end_line || span.start_line
        {max(1, span.start_line - context_lines), end_line + context_lines}
      end)

    # Merge all ranges.
    ranges =
      (inline_ranges ++ bracket_ranges)
      |> Enum.sort()
      |> merge_ranges()

    padding = String.duplicate(" ", line_num_width)

    # Format lines within each range, with gap markers between ranges.
    formatted_lines =
      ranges
      |> Enum.with_index()
      |> Enum.flat_map(fn {{range_start, range_end}, index} ->
        gap =
          if index > 0 do
            [format_gap_marker(padding, bracket_col_count, use_colors)]
          else
            []
          end

        lines =
          range_start..range_end
          |> Enum.flat_map(fn line_num ->
            source_lines =
              case Source.line(source, line_num) do
                nil ->
                  []

                source_line ->
                  bracket_prefix =
                    format_bracket_prefix(line_num, bracket_map, bracket_col_count, use_colors)

                  case Map.get(label_map, line_num) do
                    nil ->
                      [
                        format_context_line(
                          line_num,
                          source_line,
                          line_num_width,
                          bracket_prefix,
                          use_colors,
                          highlights
                        )
                      ]

                    labels_on_line ->
                      format_labels_on_line(
                        labels_on_line,
                        source_line,
                        line_num,
                        line_num_width,
                        bracket_prefix,
                        bracket_col_count,
                        use_colors,
                        highlights
                      )
                  end
              end

            # Emit bracket closing lines for brackets that end on this line.
            bracket_closings =
              format_bracket_closings(
                line_num,
                bracket_labels,
                bracket_map,
                bracket_col_count,
                padding,
                use_colors
              )

            source_lines ++ bracket_closings
          end)

        gap ++ lines
      end)

    if Enum.empty?(formatted_lines) do
      nil
    else
      Enum.join(formatted_lines, "\n")
    end
  end

  # ============================================================================
  # Bracket Label Helpers
  # ============================================================================

  # Builds a map of %{line_number => [bracket_label]} for every line in each
  # bracket's range. When multiple brackets overlap, a line maps to multiple
  # labels. Labels are kept in the order they appear in the input list so that
  # the leftmost bracket in the list gets the leftmost column.
  defp compute_bracket_map([]), do: %{}

  defp compute_bracket_map(bracket_labels) do
    Enum.reduce(bracket_labels, %{}, fn label, acc ->
      span = Label.resolved_span(label)
      end_line = span.end_line || span.start_line

      span.start_line..end_line
      |> Enum.reduce(acc, fn line, inner_acc ->
        Map.update(inner_acc, line, [label], &(&1 ++ [label]))
      end)
    end)
  end

  # Returns the maximum number of bracket columns needed across all lines.
  defp compute_bracket_col_count(bracket_map) when map_size(bracket_map) == 0, do: 0

  defp compute_bracket_col_count(bracket_map) do
    bracket_map
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.max()
  end

  # Formats the bracket prefix for a given line. Active brackets get `┃ `,
  # inactive bracket columns get `  ` for alignment.
  defp format_bracket_prefix(_line_num, _bracket_map, 0, _use_colors), do: ""

  defp format_bracket_prefix(line_num, bracket_map, bracket_col_count, use_colors) do
    active_labels = Map.get(bracket_map, line_num, [])

    0..(bracket_col_count - 1)
    |> Enum.map_join("", fn col_idx ->
      case Enum.at(active_labels, col_idx) do
        nil ->
          "  "

        label ->
          if use_colors do
            color = priority_color(label.priority)
            "#{color}#{@box.bracket_bar}#{@colors.reset} "
          else
            "#{@box.bracket_bar} "
          end
      end
    end)
  end

  # Emits closing lines for bracket labels whose end_line matches line_num.
  # The ╰── tail is placed at the bracket's column so it aligns with the ┃ bars.
  # Horizontal dashes extend through any remaining bracket columns to the right.
  defp format_bracket_closings(
         line_num,
         bracket_labels,
         bracket_map,
         bracket_col_count,
         padding,
         use_colors
       ) do
    closing_labels =
      Enum.filter(bracket_labels, fn label ->
        span = Label.resolved_span(label)
        end_line = span.end_line || span.start_line
        end_line == line_num
      end)

    Enum.map(closing_labels, fn label ->
      message = label.message || ""
      active_labels = Map.get(bracket_map, line_num, [])
      closing_col_idx = Enum.find_index(active_labels, &(&1 == label)) || 0

      pre_prefix = bracket_bars(active_labels, closing_col_idx, use_colors)

      # Extend dashes through remaining bracket columns after the closing one.
      remaining_cols = bracket_col_count - closing_col_idx - 1
      dash_ext = String.duplicate(@box.horizontal <> @box.horizontal, remaining_cols)

      color = if use_colors, do: priority_color(label.priority), else: ""

      if use_colors do
        "#{padding} #{@colors.dim}#{@box.dot}#{@colors.reset} #{pre_prefix}#{color}#{@box.bottom_left}#{@box.horizontal}#{dash_ext}#{@box.horizontal} #{message}#{@colors.reset}"
      else
        "#{padding} #{@box.dot} #{pre_prefix}#{@box.bottom_left}#{@box.horizontal}#{dash_ext}#{@box.horizontal} #{message}"
      end
    end)
  end

  # Bars for the active brackets in the columns before the closing one.
  defp bracket_bars(_active_labels, 0, _use_colors), do: ""

  defp bracket_bars(active_labels, closing_col_idx, use_colors) do
    Enum.map_join(0..(closing_col_idx - 1)//1, fn col_idx ->
      case Enum.at(active_labels, col_idx) do
        nil -> "  "
        other_label -> bracket_bar(other_label, use_colors)
      end
    end)
  end

  defp bracket_bar(label, true) do
    color = priority_color(label.priority)
    "#{color}#{@box.bracket_bar}#{@colors.reset} "
  end

  defp bracket_bar(_label, false), do: "#{@box.bracket_bar} "

  # Computes merged display ranges from a list of label line numbers.
  # Each label gets context_lines above and below. Overlapping or
  # adjacent ranges are merged into single contiguous chunks.
  defp compute_display_ranges(span_lines, context_lines) do
    span_lines
    |> Enum.map(fn line -> {max(1, line - context_lines), line + context_lines} end)
    |> Enum.sort()
    |> merge_ranges()
  end

  defp merge_ranges([]), do: []

  defp merge_ranges([first | rest]) do
    rest
    |> Enum.reduce([first], fn {start, finish}, [{acc_start, acc_end} | acc_rest] ->
      if start <= acc_end + 1 do
        # Ranges overlap or are adjacent — merge.
        [{acc_start, max(acc_end, finish)} | acc_rest]
      else
        # Gap — start a new range.
        [{start, finish}, {acc_start, acc_end} | acc_rest]
      end
    end)
    |> Enum.reverse()
  end

  defp format_gap_marker(padding, bracket_col_count, use_colors) do
    bracket_space = String.duplicate("  ", bracket_col_count)

    if use_colors do
      "#{padding} #{@colors.dim}⋮#{@colors.reset}#{bracket_space}"
    else
      "#{padding} ⋮#{bracket_space}"
    end
  end

  defp format_context_line(
         line_num,
         source_line,
         line_num_width,
         bracket_prefix,
         use_colors,
         highlights
       ) do
    line_str = String.pad_leading(Integer.to_string(line_num), line_num_width)
    prefix_width = line_num_width + 3
    truncated_line = render_source_text(source_line, prefix_width, highlights, line_num)

    if use_colors do
      "#{@colors.dim}#{line_str} #{@box.vertical}#{@colors.reset} #{bracket_prefix}#{truncated_line}"
    else
      "#{line_str} #{@box.vertical} #{bracket_prefix}#{truncated_line}"
    end
  end

  defp format_labels_on_line(
         labels,
         source_line,
         line_num,
         line_num_width,
         bracket_prefix,
         bracket_col_count,
         use_colors,
         highlights
       ) do
    padding = String.duplicate(" ", line_num_width)
    line_str = String.pad_leading(Integer.to_string(line_num), line_num_width)
    prefix_width = line_num_width + 3
    truncated_line = render_source_text(source_line, prefix_width, highlights, line_num)

    source =
      if use_colors do
        "#{@colors.dim}#{line_str}#{@colors.reset} #{@colors.dim}#{@box.vertical}#{@colors.reset} #{bracket_prefix}#{truncated_line}"
      else
        "#{line_str} #{@box.vertical} #{bracket_prefix}#{truncated_line}"
      end

    # Bracket padding for pointer lines (spaces for alignment).
    pointer_bracket_pad = String.duplicate("  ", bracket_col_count)

    # For single label, use simple rendering (no collision possible).
    if length(labels) == 1 do
      pointer_lines =
        labels
        |> Enum.flat_map(fn label ->
          format_single_label_pointer(
            label,
            source_line,
            padding,
            pointer_bracket_pad,
            use_colors
          )
        end)

      [source | pointer_lines]
    else
      # Multiple labels: use collision-aware rendering.
      pointer_lines =
        format_multi_label_pointers(labels, source_line, padding, pointer_bracket_pad, use_colors)

      [source | pointer_lines]
    end
  end

  # Renders multiple labels with collision avoidance.
  # Labels are sorted right-to-left, with rightmost getting the closest position
  # to its underline. Vertical connectors extend down for labels further left.
  defp format_multi_label_pointers(labels, source_line, padding, bracket_pad, use_colors) do
    # Phase 1: Compute geometry for each label.
    geometries =
      Enum.map(labels, fn label ->
        compute_label_geometry(label, source_line, use_colors)
      end)

    # Phase 2: Sort right-to-left by tee column (rightmost first).
    sorted = Enum.sort_by(geometries, fn g -> -g.tee_col end)

    # Phase 3: Group into underline rows based on overlap.
    underline_groups = group_underlines_by_overlap(sorted)

    # Phase 4: Assign message row indices.
    # Rightmost label (first in sorted) gets message row 0, next gets 1, etc.
    geometries_with_rows = Enum.with_index(sorted)

    # Phase 5: Render underline rows.
    # For underline rows after the first, we need connectors for labels whose
    # underlines are on earlier rows but whose messages come later.
    underline_lines =
      underline_groups
      |> Enum.with_index()
      |> Enum.flat_map(fn {group, underline_row_idx} ->
        # Connectors needed: labels whose underlines are on earlier rows.
        # These labels' tees need vertical connectors through this row.
        connector_cols =
          underline_groups
          |> Enum.take(underline_row_idx)
          |> List.flatten()
          |> Enum.map(fn g -> g.tee_col end)
          |> MapSet.new()

        render_underline_row(group, connector_cols, padding, bracket_pad, use_colors)
      end)

    # Phase 6: Render message rows with connectors.
    message_lines =
      geometries_with_rows
      |> Enum.flat_map(fn {geom, row_idx} ->
        # Connector columns: tee columns of labels that haven't rendered yet.
        connector_cols =
          geometries_with_rows
          |> Enum.filter(fn {_, idx} -> idx > row_idx end)
          |> Enum.map(fn {g, _} -> g.tee_col end)
          |> MapSet.new()

        render_message_row(geom, connector_cols, padding, bracket_pad, use_colors)
      end)

    underline_lines ++ message_lines
  end

  # Computes geometry for a single label.
  defp compute_label_geometry(label, source_line, use_colors) do
    span = Label.resolved_span(label)
    start_col = span.start_column || 1
    width = estimate_span_width(span, source_line, start_col)
    end_col = start_col + width
    tee_col = start_col + div(width - 1, 2)
    color = if use_colors, do: priority_color(label.priority), else: ""

    %{
      start_col: start_col,
      end_col: end_col,
      width: width,
      tee_col: tee_col,
      message: label.message || "",
      priority: label.priority,
      color: color
    }
  end

  # Groups geometries into underline rows based on overlap.
  # Returns list of lists, where each inner list contains non-overlapping geometries.
  defp group_underlines_by_overlap(sorted_geometries) do
    Enum.reduce(sorted_geometries, [], fn geom, groups ->
      # Try to find an existing group where this geometry doesn't overlap.
      case find_non_overlapping_group(groups, geom) do
        {:ok, group_idx} ->
          List.update_at(groups, group_idx, fn group -> group ++ [geom] end)

        :none ->
          # Create new group for this geometry.
          groups ++ [[geom]]
      end
    end)
  end

  defp find_non_overlapping_group(groups, geom) do
    groups
    |> Enum.with_index()
    |> Enum.find_value(:none, fn {group, idx} ->
      if Enum.all?(group, fn g -> not underlines_overlap?(g, geom) end) do
        {:ok, idx}
      else
        nil
      end
    end)
  end

  # Two underlines overlap if their column ranges intersect.
  defp underlines_overlap?(geom1, geom2) do
    geom1.start_col < geom2.end_col and geom2.start_col < geom1.end_col
  end

  # Renders a single underline row containing multiple non-overlapping geometries.
  # Also renders vertical connectors for labels from earlier underline rows.
  defp render_underline_row(geometries, connector_cols, padding, bracket_pad, use_colors) do
    # Find the rightmost column we need to render (consider both underlines and connectors).
    max_col_from_geoms = Enum.max_by(geometries, fn g -> g.end_col end).end_col

    max_col_from_connectors =
      if MapSet.size(connector_cols) > 0 do
        Enum.max(connector_cols)
      else
        0
      end

    max_col = max(max_col_from_geoms, max_col_from_connectors)

    # Build the underline character by character.
    chars =
      1..max_col
      |> Enum.map_join("", fn col ->
        # Check if this column is a tee position.
        tee_geom = Enum.find(geometries, fn g -> g.tee_col == col end)

        # Check if this column is part of any underline.
        underline_geom =
          Enum.find(geometries, fn g ->
            col >= g.start_col and col < g.end_col
          end)

        # Check if this column needs a vertical connector.
        is_connector = MapSet.member?(connector_cols, col)

        cond do
          tee_geom != nil ->
            # Tee position: use color of that label.
            if use_colors do
              "#{tee_geom.color}#{@box.tee_down}#{@colors.reset}"
            else
              @box.tee_down
            end

          underline_geom != nil ->
            # Part of underline: use color of that label.
            if use_colors do
              "#{underline_geom.color}#{@box.horizontal}#{@colors.reset}"
            else
              @box.horizontal
            end

          is_connector ->
            # Vertical connector for label from earlier row.
            if use_colors do
              "#{@colors.dim}#{@box.vertical}#{@colors.reset}"
            else
              @box.vertical
            end

          true ->
            " "
        end
      end)

    line =
      if use_colors do
        "#{padding} #{@colors.dim}#{@box.dot}#{@colors.reset} #{bracket_pad}#{chars}"
      else
        "#{padding} #{@box.dot} #{bracket_pad}#{chars}"
      end

    [line]
  end

  # Renders a message row with vertical connectors for labels not yet rendered.
  defp render_message_row(geom, connector_cols, padding, bracket_pad, use_colors) do
    # The message appears after the branch symbol.
    # Format: spaces... connector... spaces... ╰── message

    # Build character by character up to the tee column.
    max_col = geom.tee_col

    chars =
      1..max_col
      |> Enum.map_join("", fn col ->
        cond do
          col == geom.tee_col ->
            # This label's branch point.
            if use_colors do
              "#{geom.color}#{@box.bottom_left}#{@colors.reset}"
            else
              @box.bottom_left
            end

          MapSet.member?(connector_cols, col) ->
            # Vertical connector for a label further left.
            # Find the geometry for this connector to get its color.
            if use_colors do
              "#{@colors.dim}#{@box.vertical}#{@colors.reset}"
            else
              @box.vertical
            end

          true ->
            " "
        end
      end)

    # Add the horizontal line and message.
    branch_suffix =
      if use_colors do
        "#{geom.color}#{@box.horizontal}#{@box.horizontal} #{geom.message}#{@colors.reset}"
      else
        "#{@box.horizontal}#{@box.horizontal} #{geom.message}"
      end

    line =
      if use_colors do
        "#{padding} #{@colors.dim}#{@box.dot}#{@colors.reset} #{bracket_pad}#{chars}#{branch_suffix}"
      else
        "#{padding} #{@box.dot} #{bracket_pad}#{chars}#{branch_suffix}"
      end

    [line]
  end

  # Single label pointer rendering (original simple logic).
  defp format_single_label_pointer(label, source_line, padding, bracket_pad, use_colors) do
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
        "#{padding} #{@colors.dim}#{@box.dot}#{@colors.reset} #{bracket_pad}#{pointer_padding}#{span_color}#{underline}#{@colors.reset}"

      label_line =
        "#{padding} #{@colors.dim}#{@box.dot}#{@colors.reset} #{bracket_pad}#{branch_padding}#{span_color}#{@box.bottom_left}#{@box.horizontal}#{@box.horizontal} #{label_text}#{@colors.reset}"

      [underline_line, label_line]
    else
      underline_line = "#{padding} #{@box.dot} #{bracket_pad}#{pointer_padding}#{underline}"

      label_line =
        "#{padding} #{@box.dot} #{bracket_pad}#{branch_padding}#{@box.bottom_left}#{@box.horizontal}#{@box.horizontal} #{label_text}"

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
      |> Enum.map_join("\n", fn note -> format_note(note, line_num_width, use_colors) end)
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
      |> Enum.map_join("\n", fn h -> format_help_item(h, line_num_width, use_colors) end)
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
      |> Enum.flat_map(fn label ->
        case Label.resolved_span(label) do
          %Span.Position{start_line: line, end_line: end_line} ->
            # Account for end_line of bracket labels (may be larger).
            [line + context_lines, (end_line || line) + context_lines]

          _ ->
            [1]
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

  # Renders the visible portion of a source line, syntax-highlighted when a
  # highlight map is active and covers this line. The plain path (highlights
  # nil — always the case when colors are off) is byte-identical to
  # truncate_source_line/2. Stripping the ANSI escapes from the styled path
  # yields the plain path's exact output: the visible prefix is computed from
  # the raw line with the same length/slice calls, and styles are mapped onto
  # it afterwards.
  defp render_source_text(source_line, prefix_width, nil, _line_num) do
    truncate_source_line(source_line, prefix_width)
  end

  defp render_source_text(source_line, prefix_width, highlights, line_num) do
    case Map.get(highlights, line_num) do
      nil ->
        truncate_source_line(source_line, prefix_width)

      segments ->
        if segments_text(segments) == source_line do
          styled_source_text(segments, source_line, max_content_width(prefix_width))
        else
          # The highlighter's segments disagree with the raw line; never
          # risk changing visible characters or pointer alignment.
          truncate_source_line(source_line, prefix_width)
        end
    end
  end

  defp segments_text(segments) do
    Enum.map_join(segments, fn {_style, text} -> text end)
  end

  defp styled_source_text(segments, source_line, max_width) do
    if String.length(source_line) > max_width do
      visible = String.slice(source_line, 0, max_width - 1)

      segments
      |> take_segment_bytes(byte_size(visible), [])
      |> render_segments()
      |> Kernel.<>("…")
    else
      render_segments(segments)
    end
  end

  # Takes segments up to a byte budget, splitting the boundary segment. The
  # budget is the byte size of a String.slice prefix of the concatenated
  # segment texts (verified equal to the raw line), so the binary_part split
  # lands on a codepoint boundary and yields valid UTF-8.
  defp take_segment_bytes(_segments, 0, acc), do: Enum.reverse(acc)
  defp take_segment_bytes([], _budget, acc), do: Enum.reverse(acc)

  defp take_segment_bytes([{style, text} | rest], budget, acc) do
    size = byte_size(text)

    if size <= budget do
      take_segment_bytes(rest, budget - size, [{style, text} | acc])
    else
      Enum.reverse([{style, binary_part(text, 0, budget)} | acc])
    end
  end

  # Every styled segment closes itself with a reset, so no style is ever
  # active at end of line or bleeding into pointer rows; the truncation
  # ellipsis stays unstyled.
  defp render_segments(segments) do
    Enum.map_join(segments, fn
      {nil, text} -> text
      {style, text} -> style <> text <> @colors.reset
    end)
  end

  defp truncate_source_line(line, prefix_width) do
    max_content_width = max_content_width(prefix_width)

    if String.length(line) > max_content_width do
      String.slice(line, 0, max_content_width - 1) <> "…"
    else
      line
    end
  end

  defp max_content_width(prefix_width), do: max(@max_source_width - prefix_width, 20)

  defp bold_backtick_content(text, false), do: text

  defp bold_backtick_content(text, true) do
    Regex.replace(~r/`([^`]+)`/, text, "`#{@colors.bold}\\1#{@colors.reset}`")
  end
end
