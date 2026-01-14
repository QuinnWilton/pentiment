defprotocol Pentiment.Spannable do
  @moduledoc """
  Protocol for converting values to spans.

  This protocol allows any type to be used as a span source. Built-in implementations
  are provided for:

  - `Pentiment.Span.Byte` and `Pentiment.Span.Position` structs (identity)
  - Tuples in common formats (see below)
  - Ranges for byte spans

  ## Tuple Formats

  The following tuple formats are supported:

  - `{start, length}` - Byte offset span (2-tuple of integers)
  - `{line, column}` - Single-point position span (when both are positive)
  - `{start_line, start_col, end_line, end_col}` - Position range (4-tuple)

  Note: `{start, length}` and `{line, column}` are ambiguous for 2-tuples.
  By default, 2-tuples are interpreted as byte spans. Use `Pentiment.Span.position/2`
  explicitly for line/column positions, or implement this protocol for your own types.

  ## Custom Implementations

  You can implement this protocol for your own types:

      defimpl Pentiment.Spannable, for: MyApp.Token do
        def to_span(%MyApp.Token{line: l, col: c, length: len}) do
          Pentiment.Span.position(l, c, l, c + len)
        end
      end
  """

  @doc """
  Converts the value to a `Pentiment.Span.t()`.

  Returns a `Pentiment.Span.Byte` or `Pentiment.Span.Position` struct.
  """
  @spec to_span(t) :: Pentiment.Span.t()
  def to_span(value)
end

# Identity implementations for span structs.
defimpl Pentiment.Spannable, for: Pentiment.Span.Byte do
  def to_span(span), do: span
end

defimpl Pentiment.Spannable, for: Pentiment.Span.Position do
  def to_span(span), do: span
end

# Tuple implementations for common formats.
defimpl Pentiment.Spannable, for: Tuple do
  alias Pentiment.Span

  def to_span({start, length})
      when is_integer(start) and start >= 0 and is_integer(length) and length >= 1 do
    # Interpret as byte span by default.
    Span.byte(start, length)
  end

  def to_span({start_line, start_col, end_line, end_col})
      when is_integer(start_line) and start_line >= 1 and
             is_integer(start_col) and start_col >= 1 and
             is_integer(end_line) and end_line >= 1 and
             is_integer(end_col) and end_col >= 1 do
    Span.position(start_line, start_col, end_line, end_col)
  end

  def to_span(tuple) do
    raise ArgumentError, """
    Cannot convert tuple to span: #{inspect(tuple)}

    Supported tuple formats:
    - {start, length} - Byte offset span (start >= 0, length >= 1)
    - {start_line, start_col, end_line, end_col} - Position range (all >= 1)

    For a single-point position span, use Pentiment.Span.position(line, col) explicitly.
    """
  end
end

# Range implementation for byte spans.
defimpl Pentiment.Spannable, for: Range do
  alias Pentiment.Span

  def to_span(%Range{first: first, last: last, step: 1})
      when is_integer(first) and first >= 0 and is_integer(last) and last >= first do
    # Range is inclusive, so length is last - first + 1.
    Span.byte(first, last - first + 1)
  end

  def to_span(range) do
    raise ArgumentError, """
    Cannot convert range to span: #{inspect(range)}

    Ranges must be ascending with step 1 and start >= 0.
    Example: 10..20 becomes a byte span from offset 10 with length 11.
    """
  end
end
