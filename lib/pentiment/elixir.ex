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

  ## Examples

      iex> ast = quote do: x + y
      iex> Pentiment.Elixir.span_from_ast(ast)
      %Pentiment.Span.Position{start_line: ..., start_column: ...}

      iex> Pentiment.Elixir.span_from_ast(:not_ast)
      nil
  """
  @spec span_from_ast(Macro.t() | term()) :: Span.Position.t() | nil
  def span_from_ast({_name, meta, _args}) when is_list(meta) do
    span_from_meta(meta)
  end

  def span_from_ast(%{meta: meta}) when is_list(meta) do
    span_from_meta(meta)
  end

  def span_from_ast(_), do: nil

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
