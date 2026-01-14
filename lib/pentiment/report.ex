defmodule Pentiment.Report do
  @moduledoc """
  A ready-to-use diagnostic struct with a builder API.

  Report is the default implementation of `Pentiment.Diagnostic` and provides
  a convenient builder pattern for constructing diagnostics incrementally.

  ## Examples

      # Simple error
      Pentiment.Report.error("Unexpected token")
      |> Pentiment.Report.with_code("PARSE001")
      |> Pentiment.Report.with_source("input.txt")
      |> Pentiment.Report.with_label(Pentiment.Label.primary(span, "here"))

      # Warning with multiple labels and help
      Pentiment.Report.warning("Unused variable `x`")
      |> Pentiment.Report.with_labels([
        Pentiment.Label.primary(def_span, "defined here"),
        Pentiment.Label.secondary(scope_span, "in this scope")
      ])
      |> Pentiment.Report.with_help("prefix with underscore: `_x`")

  ## Builder Functions

  All `with_*` functions return the modified report, allowing for chaining:

  - `with_code/2` - Set an error code
  - `with_source/2` - Set the primary source
  - `with_label/2` - Add a single label
  - `with_labels/2` - Add multiple labels
  - `with_help/2` - Add a help message
  - `with_note/2` - Add a note
  """

  alias Pentiment.Label

  @type severity :: :error | :warning | :info | :hint

  @type t :: %__MODULE__{
          message: String.t(),
          code: String.t() | nil,
          severity: severity(),
          source: String.t() | nil,
          labels: [Label.t()],
          help: [String.t()],
          notes: [String.t()]
        }

  @enforce_keys [:message, :severity]
  defstruct [
    :message,
    :code,
    :source,
    severity: :error,
    labels: [],
    help: [],
    notes: []
  ]

  # ============================================================================
  # Constructors
  # ============================================================================

  @doc """
  Creates a new report with the given severity and message.

  ## Examples

      iex> Pentiment.Report.build(:error, "Something went wrong")
      %Pentiment.Report{severity: :error, message: "Something went wrong"}
  """
  @spec build(severity(), String.t()) :: t()
  def build(severity, message)
      when severity in [:error, :warning, :info, :hint] and is_binary(message) do
    %__MODULE__{severity: severity, message: message}
  end

  @doc """
  Creates an error report.

  ## Examples

      iex> Pentiment.Report.error("Type mismatch")
      %Pentiment.Report{severity: :error, message: "Type mismatch"}
  """
  @spec error(String.t()) :: t()
  def error(message), do: build(:error, message)

  @doc """
  Creates a warning report.

  ## Examples

      iex> Pentiment.Report.warning("Unused variable")
      %Pentiment.Report{severity: :warning, message: "Unused variable"}
  """
  @spec warning(String.t()) :: t()
  def warning(message), do: build(:warning, message)

  @doc """
  Creates an info report.

  ## Examples

      iex> Pentiment.Report.info("Compiling module")
      %Pentiment.Report{severity: :info, message: "Compiling module"}
  """
  @spec info(String.t()) :: t()
  def info(message), do: build(:info, message)

  @doc """
  Creates a hint report.

  ## Examples

      iex> Pentiment.Report.hint("Consider using pattern matching")
      %Pentiment.Report{severity: :hint, message: "Consider using pattern matching"}
  """
  @spec hint(String.t()) :: t()
  def hint(message), do: build(:hint, message)

  # ============================================================================
  # Builder Functions
  # ============================================================================

  @doc """
  Sets the error code.

  ## Examples

      iex> report |> Pentiment.Report.with_code("E0001")
  """
  @spec with_code(t(), String.t()) :: t()
  def with_code(%__MODULE__{} = report, code) when is_binary(code) do
    %{report | code: code}
  end

  @doc """
  Sets the primary source identifier.

  ## Examples

      iex> report |> Pentiment.Report.with_source("lib/my_app.ex")
  """
  @spec with_source(t(), String.t()) :: t()
  def with_source(%__MODULE__{} = report, source) when is_binary(source) do
    %{report | source: source}
  end

  @doc """
  Adds a single label.

  ## Examples

      iex> report |> Pentiment.Report.with_label(Label.primary(span, "error here"))
  """
  @spec with_label(t(), Label.t()) :: t()
  def with_label(%__MODULE__{labels: labels} = report, %Label{} = label) do
    %{report | labels: labels ++ [label]}
  end

  @doc """
  Adds multiple labels.

  ## Examples

      iex> report |> Pentiment.Report.with_labels([
      ...>   Label.secondary(decl_span, "declared here"),
      ...>   Label.primary(use_span, "used here")
      ...> ])
  """
  @spec with_labels(t(), [Label.t()]) :: t()
  def with_labels(%__MODULE__{labels: labels} = report, new_labels) when is_list(new_labels) do
    %{report | labels: labels ++ new_labels}
  end

  @doc """
  Adds a help message.

  ## Examples

      iex> report |> Pentiment.Report.with_help("Try using `trunc/1`")
  """
  @spec with_help(t(), String.t()) :: t()
  def with_help(%__MODULE__{help: help} = report, message) when is_binary(message) do
    %{report | help: help ++ [message]}
  end

  @doc """
  Adds a note.

  ## Examples

      iex> report |> Pentiment.Report.with_note("Function expects integer arguments")
  """
  @spec with_note(t(), String.t()) :: t()
  def with_note(%__MODULE__{notes: notes} = report, message) when is_binary(message) do
    %{report | notes: notes ++ [message]}
  end

  # ============================================================================
  # Diagnostic Protocol Implementation
  # ============================================================================

  defimpl Pentiment.Diagnostic do
    def message(%{message: m}), do: m
    def code(%{code: c}), do: c
    def severity(%{severity: s}), do: s
    def source(%{source: s}), do: s
    def labels(%{labels: l}), do: l
    def help(%{help: h}), do: h
    def notes(%{notes: n}), do: n
  end
end
