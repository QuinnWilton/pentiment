defmodule Pentiment do
  @moduledoc """
  Beautiful, informative compiler-style error messages for Elixir.

  Pentiment provides rich diagnostic formatting with highlighted source spans,
  helpful suggestions, and clear error context. It's designed for:

  - Compile-time macro errors
  - DSL validation
  - Parser error reporting
  - Configuration file validation

  ## Quick Start

      # Create a diagnostic
      report = Pentiment.Report.error("Type mismatch")
        |> Pentiment.Report.with_code("E0001")
        |> Pentiment.Report.with_source("lib/my_app.ex")
        |> Pentiment.Report.with_label(
          Pentiment.Label.primary(Pentiment.Span.position(15, 10), "expected `integer`, found `float`")
        )
        |> Pentiment.Report.with_help("Use `trunc/1` to convert")

      # Format and display
      IO.puts(Pentiment.format(report, source))

  ## Output Example

      error[E0001]: Type mismatch
         ╭─[lib/my_app.ex:15:10]
         │
      14 │   add = fn x :: integer, y :: integer ->
      15 │     x + y + 1.5
         •             ────┬────
         •                 ╰── expected `integer`, found `float`
         │
         ╰─────
            help: Use `trunc/1` to convert

  ## Core Concepts

  - **Span** - A region in source code (byte offset or line/column)
  - **Label** - An annotated span with a message and priority
  - **Source** - The source text to display context from
  - **Diagnostic** - The complete error/warning with all metadata
  - **Report** - A ready-to-use diagnostic struct with builder API

  ## Modules

  - `Pentiment.Span` - Span types (`Byte` and `Position`)
  - `Pentiment.Spannable` - Protocol for custom span types
  - `Pentiment.Label` - Labeled spans for annotations
  - `Pentiment.Source` - Source text representation
  - `Pentiment.Diagnostic` - Protocol for diagnostic types
  - `Pentiment.Report` - Default diagnostic struct with builder API
  - `Pentiment.Formatter.Renderer` - Rich multi-line formatter
  - `Pentiment.Formatter.Compact` - Single-line formatter
  - `Pentiment.Elixir` - Helpers for Elixir AST integration
  """

  alias Pentiment.{Diagnostic, Source}
  alias Pentiment.Formatter.Renderer

  @type format_options :: [
          colors: boolean(),
          context_lines: non_neg_integer(),
          formatter: module()
        ]

  @doc """
  Formats a diagnostic for display.

  ## Arguments

  - `diagnostic` - Any struct implementing `Pentiment.Diagnostic`
  - `sources` - Source content, can be:
    - A `Pentiment.Source` struct
    - A map of source names to content strings
    - A map of source names to `Pentiment.Source` structs
    - A file path string (will be read from disk)

  ## Options

  - `:colors` - Whether to use ANSI colors (default: true)
  - `:context_lines` - Lines of context around labels (default: 2)
  - `:formatter` - Formatter module (default: `Pentiment.Formatter.Renderer`)

  ## Examples

      # With a Source struct
      source = Pentiment.Source.from_file("lib/app.ex")
      Pentiment.format(report, source)

      # With a map of sources
      Pentiment.format(report, %{"lib/app.ex" => File.read!("lib/app.ex")})

      # With a file path (reads from disk)
      Pentiment.format(report, "lib/app.ex")

      # Without colors
      Pentiment.format(report, source, colors: false)
  """
  @spec format(Diagnostic.t(), Source.t() | map() | String.t(), format_options()) :: String.t()
  def format(diagnostic, sources, opts \\ []) do
    sources = normalize_sources(sources, diagnostic)
    formatter = Keyword.get(opts, :formatter, Renderer)
    formatter.format(diagnostic, sources, opts)
  end

  @doc """
  Formats multiple diagnostics for display.

  ## Arguments

  - `diagnostics` - List of structs implementing `Pentiment.Diagnostic`
  - `sources` - Source content (same formats as `format/3`)
  - `opts` - Formatting options (same as `format/3`)

  ## Examples

      errors = [error1, error2, error3]
      IO.puts(Pentiment.format_all(errors, sources))
  """
  @spec format_all([Diagnostic.t()], Source.t() | map() | String.t(), format_options()) ::
          String.t()
  def format_all(diagnostics, sources, opts \\ []) when is_list(diagnostics) do
    sources = normalize_sources_for_all(sources, diagnostics)
    formatter = Keyword.get(opts, :formatter, Renderer)
    formatter.format_all(diagnostics, sources, opts)
  end

  @doc """
  Formats a diagnostic as a single line (compact format).

  Useful for log output or machine-parseable formats.

  ## Examples

      report = Pentiment.Report.error("Type mismatch")
        |> Pentiment.Report.with_code("E0001")
        |> Pentiment.Report.with_source("lib/app.ex")
        |> Pentiment.Report.with_label(Pentiment.Label.primary(Pentiment.Span.position(15, 10), "here"))

      Pentiment.format_compact(report)
      # => "[E0001] Type mismatch (lib/app.ex:15:10)"
  """
  @spec format_compact(Diagnostic.t()) :: String.t()
  def format_compact(diagnostic) do
    Pentiment.Formatter.Compact.format(diagnostic)
  end

  # ============================================================================
  # Source Normalization
  # ============================================================================

  defp normalize_sources(%Source{} = source, _diagnostic), do: source

  defp normalize_sources(sources, _diagnostic) when is_map(sources), do: sources

  defp normalize_sources(path, diagnostic) when is_binary(path) do
    # If it's a file path, create a source map.
    source_name = Diagnostic.source(diagnostic) || path

    if File.exists?(path) do
      %{source_name => Source.from_file(path)}
    else
      %{}
    end
  end

  defp normalize_sources(nil, _diagnostic), do: %{}

  defp normalize_sources_for_all(%Source{} = source, _diagnostics), do: source

  defp normalize_sources_for_all(sources, _diagnostics) when is_map(sources), do: sources

  defp normalize_sources_for_all(path, diagnostics) when is_binary(path) do
    # Collect all unique source names from diagnostics.
    source_names =
      diagnostics
      |> Enum.map(&Diagnostic.source/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # If the path matches a source name or we only have one source, use it.
    if File.exists?(path) do
      source = Source.from_file(path)

      source_names
      |> Enum.map(fn name -> {name, source} end)
      |> Map.new()
    else
      %{}
    end
  end

  defp normalize_sources_for_all(nil, _diagnostics), do: %{}
end
