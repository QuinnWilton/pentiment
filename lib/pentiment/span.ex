defmodule Pentiment.Span do
  @moduledoc """
  Span types for representing regions in source code.

  Pentiment supports three span representations:

  - `Pentiment.Span.Byte` - Byte offset spans, ideal for parsers that track byte positions
  - `Pentiment.Span.Position` - Line/column spans, ideal for Elixir macros and AST metadata
  - `Pentiment.Span.Search` - Deferred spans that search for a pattern at format time

  The first two can be used interchangeably through the `Pentiment.Spannable` protocol.
  Search spans are resolved to Position spans when the diagnostic is formatted.

  ## Examples

      # Byte offset span: starts at byte 42, spans 10 bytes
      Pentiment.Span.byte(42, 10)

      # Line/column span: line 5, columns 10-20
      Pentiment.Span.position(5, 10, 5, 20)

      # Single-point span (just a position)
      Pentiment.Span.position(5, 10)

      # Deferred search span: find "error" on line 5
      Pentiment.Span.search(line: 5, pattern: "error")
  """

  @type t :: __MODULE__.Byte.t() | __MODULE__.Position.t() | __MODULE__.Search.t()

  # ============================================================================
  # Byte Offset Span
  # ============================================================================

  defmodule Byte do
    @moduledoc """
    A span defined by byte offset and length.

    This representation is common in parsers (like nimble_parsec) where positions
    are tracked as byte offsets into the source text.

    ## Fields

    - `:start` - The starting byte offset (0-indexed)
    - `:length` - The number of bytes in the span (minimum 1)
    """

    @type t :: %__MODULE__{
            start: non_neg_integer(),
            length: pos_integer()
          }

    @enforce_keys [:start, :length]
    defstruct [:start, :length]

    @doc """
    Creates a new byte span.

    ## Examples

        iex> Pentiment.Span.Byte.new(42, 10)
        %Pentiment.Span.Byte{start: 42, length: 10}
    """
    @spec new(non_neg_integer(), pos_integer()) :: t()
    def new(start, length)
        when is_integer(start) and start >= 0 and is_integer(length) and length >= 1 do
      %__MODULE__{start: start, length: length}
    end

    @doc """
    Resolves a byte span against source content, returning a Position span.

    Converts byte offsets to line/column positions using the source content.
    Returns a Position span covering the byte range, or falls back to a point
    span at line 1, column 1 if the source is nil or offsets are invalid.

    ## Examples

        iex> source = Pentiment.Source.from_string("test", "hello world")
        iex> byte_span = Pentiment.Span.Byte.new(6, 5)
        iex> Pentiment.Span.Byte.resolve(byte_span, source)
        %Pentiment.Span.Position{start_line: 1, start_column: 7, end_line: 1, end_column: 12}
    """
    @spec resolve(t(), Pentiment.Source.t() | nil) :: Pentiment.Span.Position.t()
    def resolve(%__MODULE__{}, nil) do
      # No source available, fall back to point span.
      Pentiment.Span.Position.new(1, 1)
    end

    def resolve(%__MODULE__{start: start, length: length}, source) do
      case Pentiment.Source.byte_to_position(source, start) do
        nil ->
          # Invalid start offset, fall back to point span.
          Pentiment.Span.Position.new(1, 1)

        {start_line, start_col} ->
          # Calculate end position (exclusive, so start + length).
          end_offset = start + length

          case Pentiment.Source.byte_to_position(source, end_offset) do
            nil ->
              # End offset is beyond content; use start as a point span.
              Pentiment.Span.Position.new(start_line, start_col)

            {end_line, end_col} ->
              Pentiment.Span.Position.new(start_line, start_col, end_line, end_col)
          end
      end
    end
  end

  # ============================================================================
  # Line/Column Position Span
  # ============================================================================

  defmodule Position do
    @moduledoc """
    A span defined by line and column positions.

    This representation matches Elixir's AST metadata format, making it ideal
    for compile-time macros and DSLs. Lines are 1-indexed, columns are 1-indexed.

    ## Fields

    - `:start_line` - The starting line number (1-indexed, required)
    - `:start_column` - The starting column number (1-indexed, optional, defaults to 1)
    - `:end_line` - The ending line number (optional, defaults to start_line)
    - `:end_column` - The ending column number (optional)

    When `end_line` and `end_column` are nil, the span represents a single point.
    """

    @type t :: %__MODULE__{
            start_line: pos_integer(),
            start_column: pos_integer(),
            end_line: pos_integer() | nil,
            end_column: pos_integer() | nil
          }

    @enforce_keys [:start_line]
    defstruct [
      :start_line,
      start_column: 1,
      end_line: nil,
      end_column: nil
    ]

    @doc """
    Creates a new position span.

    ## Examples

        # Full range
        iex> Pentiment.Span.Position.new(5, 10, 5, 20)
        %Pentiment.Span.Position{start_line: 5, start_column: 10, end_line: 5, end_column: 20}

        # Single point
        iex> Pentiment.Span.Position.new(5, 10)
        %Pentiment.Span.Position{start_line: 5, start_column: 10, end_line: nil, end_column: nil}
    """
    @spec new(pos_integer(), pos_integer(), pos_integer() | nil, pos_integer() | nil) :: t()
    def new(start_line, start_column \\ 1, end_line \\ nil, end_column \\ nil)
        when is_integer(start_line) and start_line >= 1 and
               is_integer(start_column) and start_column >= 1 do
      %__MODULE__{
        start_line: start_line,
        start_column: start_column,
        end_line: end_line,
        end_column: end_column
      }
    end

    @doc """
    Returns true if this span represents a single point (no end position).
    """
    @spec point?(t()) :: boolean()
    def point?(%__MODULE__{end_line: nil, end_column: nil}), do: true
    def point?(%__MODULE__{}), do: false

    @doc """
    Returns the span as a range on a single line, or nil if it spans multiple lines.

    Returns `{line, start_col, end_col}` if on a single line, `nil` otherwise.
    """
    @spec single_line_range(t()) :: {pos_integer(), pos_integer(), pos_integer()} | nil
    def single_line_range(%__MODULE__{
          start_line: line,
          start_column: start_col,
          end_line: nil,
          end_column: nil
        }) do
      # Point span - treat as single character.
      {line, start_col, start_col + 1}
    end

    def single_line_range(%__MODULE__{
          start_line: line,
          start_column: start_col,
          end_line: line,
          end_column: end_col
        })
        when is_integer(end_col) do
      {line, start_col, end_col}
    end

    def single_line_range(%__MODULE__{}), do: nil
  end

  # ============================================================================
  # Deferred Search Span
  # ============================================================================

  defmodule Search do
    @moduledoc """
    A deferred span that searches for a pattern at format time.

    Search spans are resolved when the diagnostic is formatted, using the
    source content to find the pattern and determine exact positions. This
    is useful when span positions aren't known at diagnostic creation time,
    such as in macros where keyword argument positions aren't in the AST.

    ## Fields

    - `:line` - The starting line number to search from (1-indexed, required)
    - `:pattern` - The string pattern to find (required)
    - `:after_column` - Only match patterns starting at or after this column on the first line (optional, defaults to 1)
    - `:max_lines` - Maximum number of lines to search (optional, defaults to 1)

    ## Resolution

    At format time, the search span is resolved to a `Position` span:
    - If the pattern is found, returns a span covering the match
    - If not found, falls back to a point span at `{line, after_column}`

    ## Examples

        # Search for "hoost:" on line 3
        Pentiment.Span.search(line: 3, pattern: "hoost:")

        # Search after column 10 (skip earlier matches)
        Pentiment.Span.search(line: 3, pattern: "host", after_column: 10)

        # Search across multiple lines (for multi-line constructs)
        Pentiment.Span.search(line: 3, pattern: "my_key:", max_lines: 5)
    """

    @type t :: %__MODULE__{
            line: pos_integer(),
            pattern: String.t(),
            after_column: pos_integer(),
            max_lines: pos_integer()
          }

    @enforce_keys [:line, :pattern]
    defstruct [
      :line,
      :pattern,
      after_column: 1,
      max_lines: 1
    ]

    @doc """
    Creates a new search span.

    ## Options

    - `:line` - The line number to start searching from (required)
    - `:pattern` - The pattern to find (required)
    - `:after_column` - Start searching at this column on the first line (default: 1)
    - `:max_lines` - Maximum number of lines to search (default: 1)

    ## Examples

        iex> Pentiment.Span.Search.new(line: 3, pattern: "hoost:")
        %Pentiment.Span.Search{line: 3, pattern: "hoost:", after_column: 1, max_lines: 1}

        iex> Pentiment.Span.Search.new(line: 3, pattern: "host", after_column: 10)
        %Pentiment.Span.Search{line: 3, pattern: "host", after_column: 10, max_lines: 1}

        iex> Pentiment.Span.Search.new(line: 3, pattern: "key:", max_lines: 5)
        %Pentiment.Span.Search{line: 3, pattern: "key:", after_column: 1, max_lines: 5}
    """
    @spec new(keyword()) :: t()
    def new(opts) when is_list(opts) do
      line = Keyword.fetch!(opts, :line)
      pattern = Keyword.fetch!(opts, :pattern)
      after_column = Keyword.get(opts, :after_column, 1)
      max_lines = Keyword.get(opts, :max_lines, 1)

      %__MODULE__{
        line: line,
        pattern: pattern,
        after_column: after_column,
        max_lines: max_lines
      }
    end

    @doc """
    Resolves a search span against source content, returning a Position span.

    Searches for the pattern starting from the specified line, optionally
    spanning multiple lines. Returns a Position span covering the match,
    or a point span at `{line, after_column}` if not found.
    """
    @spec resolve(t(), Pentiment.Source.t() | nil) :: Pentiment.Span.Position.t()
    def resolve(%__MODULE__{} = search, nil) do
      # No source available, fall back to point span.
      Pentiment.Span.Position.new(search.line, search.after_column)
    end

    def resolve(%__MODULE__{} = search, source) do
      search_lines(search, source, search.line, search.max_lines)
    end

    defp search_lines(search, _source, _current_line, 0) do
      # Exhausted all lines, fall back to point span.
      Pentiment.Span.Position.new(search.line, search.after_column)
    end

    defp search_lines(search, source, current_line, remaining_lines) do
      case Pentiment.Source.line(source, current_line) do
        nil ->
          # Line not found, fall back to point span.
          Pentiment.Span.Position.new(search.line, search.after_column)

        source_line ->
          # On the first line, respect after_column; on subsequent lines, start from column 1.
          search_start =
            if current_line == search.line do
              max(0, search.after_column - 1)
            else
              0
            end

          searchable = String.slice(source_line, search_start, String.length(source_line))

          case :binary.match(searchable, search.pattern) do
            {pos, len} ->
              # Found - calculate actual column (1-indexed).
              start_col = search_start + pos + 1
              end_col = start_col + len
              Pentiment.Span.Position.new(current_line, start_col, current_line, end_col)

            :nomatch ->
              # Not found on this line, try the next one.
              search_lines(search, source, current_line + 1, remaining_lines - 1)
          end
      end
    end
  end

  # ============================================================================
  # Convenience Constructors
  # ============================================================================

  @doc """
  Creates a byte offset span.

  ## Examples

      iex> Pentiment.Span.byte(42, 10)
      %Pentiment.Span.Byte{start: 42, length: 10}
  """
  @spec byte(non_neg_integer(), pos_integer()) :: Byte.t()
  def byte(start, length), do: Byte.new(start, length)

  @doc """
  Creates a line/column position span.

  Can be called with 2 arguments for a single point, or 4 arguments for a range.

  ## Examples

      # Single point at line 5, column 10
      iex> Pentiment.Span.position(5, 10)
      %Pentiment.Span.Position{start_line: 5, start_column: 10, end_line: nil, end_column: nil}

      # Range from line 5 col 10 to line 5 col 20
      iex> Pentiment.Span.position(5, 10, 5, 20)
      %Pentiment.Span.Position{start_line: 5, start_column: 10, end_line: 5, end_column: 20}
  """
  @spec position(pos_integer(), pos_integer(), pos_integer() | nil, pos_integer() | nil) ::
          Position.t()
  def position(start_line, start_column \\ 1, end_line \\ nil, end_column \\ nil) do
    Position.new(start_line, start_column, end_line, end_column)
  end

  @doc """
  Creates a deferred search span.

  Search spans are resolved at format time by searching for the pattern in
  the source content. This is useful when exact positions aren't available
  at diagnostic creation time, such as in macros.

  ## Options

  - `:line` - The starting line number to search from (required)
  - `:pattern` - The string pattern to find (required)
  - `:after_column` - Only match patterns starting at or after this column on the first line (default: 1)
  - `:max_lines` - Maximum number of lines to search (default: 1)

  ## Examples

      # Search for "hoost:" on line 3
      iex> Pentiment.Span.search(line: 3, pattern: "hoost:")
      %Pentiment.Span.Search{line: 3, pattern: "hoost:", after_column: 1, max_lines: 1}

      # Search after column 10 to skip earlier matches
      iex> Pentiment.Span.search(line: 3, pattern: "host", after_column: 10)
      %Pentiment.Span.Search{line: 3, pattern: "host", after_column: 10, max_lines: 1}

      # Search across multiple lines (for multi-line constructs)
      iex> Pentiment.Span.search(line: 3, pattern: "key:", max_lines: 5)
      %Pentiment.Span.Search{line: 3, pattern: "key:", after_column: 1, max_lines: 5}
  """
  @spec search(keyword()) :: Search.t()
  def search(opts) when is_list(opts) do
    Search.new(opts)
  end
end
