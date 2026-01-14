defmodule Pentiment.Span do
  @moduledoc """
  Span types for representing regions in source code.

  Pentiment supports two span representations:

  - `Pentiment.Span.Byte` - Byte offset spans, ideal for parsers that track byte positions
  - `Pentiment.Span.Position` - Line/column spans, ideal for Elixir macros and AST metadata

  Both can be used interchangeably through the `Pentiment.Spannable` protocol.

  ## Examples

      # Byte offset span: starts at byte 42, spans 10 bytes
      Pentiment.Span.byte(42, 10)

      # Line/column span: line 5, columns 10-20
      Pentiment.Span.position(5, 10, 5, 20)

      # Single-point span (just a position)
      Pentiment.Span.position(5, 10)
  """

  @type t :: __MODULE__.Byte.t() | __MODULE__.Position.t()

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
end
