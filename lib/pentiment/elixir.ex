defmodule Pentiment.Elixir do
  @moduledoc """
  Helpers for extracting spans from Elixir AST metadata.

  This module provides convenience functions for working with Elixir's
  compile-time metadata, making it easy to integrate Pentiment with
  macros and DSLs.

  ## Usage in Macros

      defmacro my_macro(expr) do
        span = Pentiment.Elixir.span_from_ast(expr)
        source = Pentiment.Elixir.source_from_env(__CALLER__)

        if invalid?(expr) do
          report = Pentiment.Report.error("Invalid expression")
            |> Pentiment.Report.with_source(__CALLER__.file)
            |> Pentiment.Report.with_label(Pentiment.Label.primary(span, "here"))

          raise CompileError, description: Pentiment.format(report, source)
        end

        # ... normal macro expansion
      end

  ## Metadata Keys

  Elixir AST metadata typically includes:

  - `:line` - Line number (1-indexed, always present)
  - `:column` - Column number (1-indexed, often present)
  - `:end_line` - End line for multi-line nodes (optional)
  - `:end_column` - End column (optional)
  - `:file` - File path (sometimes present)
  """

  alias Pentiment.{Source, Span}

  @doc """
  Extracts a span from Elixir AST metadata.

  Accepts a keyword list of metadata (as found in AST nodes).

  ## Examples

      iex> Pentiment.Elixir.span_from_meta([line: 10, column: 5])
      %Pentiment.Span.Position{start_line: 10, start_column: 5}

      iex> Pentiment.Elixir.span_from_meta([line: 10, column: 5, end_line: 10, end_column: 15])
      %Pentiment.Span.Position{start_line: 10, start_column: 5, end_line: 10, end_column: 15}

      iex> Pentiment.Elixir.span_from_meta([])
      nil
  """
  @spec span_from_meta(keyword()) :: Span.Position.t() | nil
  def span_from_meta(meta) when is_list(meta) do
    line = Keyword.get(meta, :line)

    if line do
      column = Keyword.get(meta, :column, 1)
      end_line = Keyword.get(meta, :end_line)
      end_column = Keyword.get(meta, :end_column)

      Span.position(line, column, end_line, end_column)
    else
      nil
    end
  end

  @doc """
  Extracts a span from an Elixir AST node.

  Works with:
  - Raw Elixir AST tuples: `{name, meta, args}`
  - Structs with a `:meta` field

  When possible, computes the end column from the AST structure:
  - Variables: uses the variable name length
  - Function calls with `:closing` metadata: uses the closing paren/bracket position
  - Maps, binaries, anonymous functions: uses closing metadata
  - Aliases: uses `:last` metadata for multi-part aliases
  - Block expressions (case, cond, etc.): uses `:end` metadata
  - Otherwise: falls back to metadata only

  ## Examples

      iex> ast = quote do: x + y
      iex> Pentiment.Elixir.span_from_ast(ast)
      %Pentiment.Span.Position{start_line: ..., start_column: ...}

      iex> Pentiment.Elixir.span_from_ast(:not_ast)
      nil
  """
  @spec span_from_ast(Macro.t() | term()) :: Span.Position.t() | nil
  def span_from_ast({name, meta, nil}) when is_atom(name) and is_list(meta) do
    # Variable node - we can compute the length from the name.
    span_from_meta_with_length(meta, atom_length(name))
  end

  def span_from_ast({:__aliases__, meta, segments}) when is_list(meta) and is_list(segments) do
    # Alias like Foo.Bar.Baz - check for :last metadata.
    line = Keyword.get(meta, :line)
    column = Keyword.get(meta, :column, 1)

    case Keyword.get(meta, :last) do
      last when is_list(last) ->
        # :last points to the last segment.
        last_segment = List.last(segments)
        last_col = Keyword.get(last, :column, column)
        last_len = if is_atom(last_segment), do: atom_length(last_segment), else: 1

        if line do
          end_line = Keyword.get(last, :line, line)
          Span.position(line, column, end_line, last_col + last_len)
        else
          nil
        end

      nil ->
        # Single-segment alias, compute from segments.
        if line && length(segments) == 1 do
          Span.position(line, column, line, column + atom_length(hd(segments)))
        else
          span_from_meta(meta)
        end
    end
  end

  def span_from_ast({name, meta, args}) when is_atom(name) and is_list(meta) and is_list(args) do
    line = Keyword.get(meta, :line)
    column = Keyword.get(meta, :column, 1)

    cond do
      # Check for :closing metadata (function calls, maps, binaries, fn, etc.).
      closing = Keyword.get(meta, :closing) ->
        end_line = Keyword.get(closing, :line, line)
        end_column = Keyword.get(closing, :column)

        if line && end_column do
          # end_column points to the closing delimiter, include it in the span.
          Span.position(line, column, end_line, end_column + 1)
        else
          span_from_meta(meta)
        end

      # Check for :end metadata (case, cond, with, receive, try, etc.).
      end_meta = Keyword.get(meta, :end) ->
        end_line = Keyword.get(end_meta, :line, line)
        end_column = Keyword.get(end_meta, :column)

        if line && end_column do
          # :end points to the 'end' keyword, include it (3 chars for "end").
          Span.position(line, column, end_line, end_column + 3)
        else
          span_from_meta(meta)
        end

      # Check for :do metadata without :end (inline do:).
      Keyword.has_key?(meta, :do) ->
        span_from_meta(meta)

      # Function call without :closing - estimate from name length.
      line && is_list(args) ->
        Span.position(line, column, line, column + atom_length(name))

      # Fallback to metadata only.
      true ->
        span_from_meta(meta)
    end
  end

  def span_from_ast(%{meta: meta}) when is_list(meta) do
    span_from_meta(meta)
  end

  def span_from_ast(_), do: nil

  # Computes span with a known length added to the start column.
  defp span_from_meta_with_length(meta, length) when is_integer(length) and length > 0 do
    line = Keyword.get(meta, :line)

    if line do
      column = Keyword.get(meta, :column, 1)
      # Check if end info is already provided.
      end_line = Keyword.get(meta, :end_line)
      end_column = Keyword.get(meta, :end_column)

      if end_column do
        # Use existing end info.
        Span.position(line, column, end_line, end_column)
      else
        # Compute end from length.
        Span.position(line, column, line, column + length)
      end
    else
      nil
    end
  end

  defp atom_length(atom) when is_atom(atom) do
    String.length(Atom.to_string(atom))
  end

  @doc """
  Creates a span for a literal value at a known position.

  Computes the display length for common Elixir literals:
  - Atoms: includes the leading colon (e.g., `:foo` = 4 chars)
  - Integers: digit count
  - Strings: includes quotes (e.g., `"hi"` = 4 chars)
  - Variables/identifiers: string length

  ## Examples

      iex> Pentiment.Elixir.span_for_value(:foo, 5, 10)
      %Pentiment.Span.Position{start_line: 5, start_column: 10, end_line: 5, end_column: 14}

      iex> Pentiment.Elixir.span_for_value(12345, 1, 1)
      %Pentiment.Span.Position{start_line: 1, start_column: 1, end_line: 1, end_column: 6}
  """
  @spec span_for_value(term(), pos_integer(), pos_integer()) :: Span.Position.t()
  def span_for_value(value, line, column) when is_integer(line) and is_integer(column) do
    length = value_display_length(value)
    Span.position(line, column, line, column + length)
  end

  @doc """
  Returns the display length of a value as it would appear in source code.

  ## Examples

      iex> Pentiment.Elixir.value_display_length(:foo)
      4  # `:foo`

      iex> Pentiment.Elixir.value_display_length(12345)
      5

      iex> Pentiment.Elixir.value_display_length("hello")
      7  # `"hello"`
  """
  @spec value_display_length(term()) :: pos_integer()
  def value_display_length(atom) when is_atom(atom) do
    # Atoms display with a leading colon.
    1 + String.length(Atom.to_string(atom))
  end

  def value_display_length(int) when is_integer(int) do
    # Count digits (including negative sign if present).
    String.length(Integer.to_string(int))
  end

  def value_display_length(float) when is_float(float) do
    String.length(Float.to_string(float))
  end

  def value_display_length(string) when is_binary(string) do
    # Strings display with surrounding quotes.
    # Note: this is a simplification - doesn't account for escape sequences.
    2 + String.length(string)
  end

  def value_display_length(_other), do: 1

  @doc """
  Extracts the leftmost span from two AST nodes.

  Useful for binary operators where the first operand typically has
  better position information.

  ## Examples

      iex> left = quote do: x
      iex> right = quote do: y
      iex> Pentiment.Elixir.leftmost_span(left, right)
      # Returns span from `left` if available, otherwise from `right`
  """
  @spec leftmost_span(term(), term()) :: Span.Position.t() | nil
  def leftmost_span(node1, node2) do
    span_from_ast(node1) || span_from_ast(node2)
  end

  @doc """
  Creates a Source from a `Macro.Env` struct.

  Reads the source file from the environment's file path.

  ## Examples

      defmacro my_macro(expr) do
        source = Pentiment.Elixir.source_from_env(__CALLER__)
        # ...
      end
  """
  @spec source_from_env(Macro.Env.t()) :: Source.t() | nil
  def source_from_env(%Macro.Env{file: file}) when is_binary(file) do
    if File.exists?(file) do
      Source.from_file(file)
    else
      Source.named(file)
    end
  end

  def source_from_env(_), do: nil

  @doc """
  Extracts file path from a `Macro.Env` struct.

  ## Examples

      iex> Pentiment.Elixir.file_from_env(__CALLER__)
      "lib/my_app.ex"
  """
  @spec file_from_env(Macro.Env.t()) :: String.t() | nil
  def file_from_env(%Macro.Env{file: file}) when is_binary(file), do: file
  def file_from_env(_), do: nil

  @doc """
  Extracts line number from a `Macro.Env` struct.

  ## Examples

      iex> Pentiment.Elixir.line_from_env(__CALLER__)
      42
  """
  @spec line_from_env(Macro.Env.t()) :: pos_integer() | nil
  def line_from_env(%Macro.Env{line: line}) when is_integer(line) and line > 0, do: line
  def line_from_env(_), do: nil

  @doc """
  Extracts a span from a `Macro.Env` struct.

  Note: `Macro.Env` only provides line information, not column.

  ## Examples

      iex> Pentiment.Elixir.span_from_env(__CALLER__)
      %Pentiment.Span.Position{start_line: 42, start_column: 1}
  """
  @spec span_from_env(Macro.Env.t()) :: Span.Position.t() | nil
  def span_from_env(%Macro.Env{line: line}) when is_integer(line) and line > 0 do
    Span.position(line, 1)
  end

  def span_from_env(_), do: nil
end
