defprotocol Pentiment.Diagnostic do
  @moduledoc """
  Protocol for types that can be rendered as diagnostics.

  Implement this protocol to enable any struct to be formatted by Pentiment.
  This is useful when you want to define domain-specific error types that
  integrate with Pentiment's rendering.

  ## Example Implementation

      defmodule MyApp.TypeError do
        defstruct [:expected, :actual, :location, :file]

        defimpl Pentiment.Diagnostic do
          def message(%{expected: e, actual: a}) do
            "Expected `\#{e}`, found `\#{a}`"
          end

          def code(_), do: "T001"
          def severity(_), do: :error
          def source(%{file: f}), do: f

          def labels(%{location: {line, col}, actual: a}) do
            [Pentiment.Label.primary(Pentiment.Span.position(line, col), "has type `\#{a}`")]
          end

          def help(_), do: ["Check your types"]
          def notes(_), do: []
        end
      end

  ## Required Callbacks

  All callbacks have default implementations that return sensible defaults,
  but you should implement at least `message/1` and `labels/1` for useful output.
  """

  @doc """
  Returns the main diagnostic message.

  This is the primary description of the error/warning shown in the header.
  """
  @spec message(t) :: String.t()
  def message(diagnostic)

  @doc """
  Returns an optional error code (e.g., "E0001", "PARSE001").

  Error codes help users look up documentation for specific errors.
  Return `nil` if no code is applicable.
  """
  @spec code(t) :: String.t() | nil
  def code(diagnostic)

  @doc """
  Returns the severity level.

  - `:error` - A problem that must be fixed
  - `:warning` - A potential issue that should be reviewed
  - `:info` - Informational message
  - `:hint` - Suggestion for improvement
  """
  @spec severity(t) :: :error | :warning | :info | :hint
  def severity(diagnostic)

  @doc """
  Returns the primary source identifier for this diagnostic.

  This is typically a file path or source name. Return `nil` if no
  specific source is associated with the diagnostic.
  """
  @spec source(t) :: String.t() | nil
  def source(diagnostic)

  @doc """
  Returns a list of labeled spans to highlight in the source.

  Labels annotate specific regions of source code with messages.
  An empty list means no source highlighting.
  """
  @spec labels(t) :: [Pentiment.Label.t()]
  def labels(diagnostic)

  @doc """
  Returns a list of help/suggestion messages.

  These are actionable suggestions for fixing the issue, displayed
  with a "help:" prefix.
  """
  @spec help(t) :: [String.t()]
  def help(diagnostic)

  @doc """
  Returns a list of additional notes.

  Notes provide extra context about the error, displayed with a
  "note:" prefix.
  """
  @spec notes(t) :: [String.t()]
  def notes(diagnostic)
end
