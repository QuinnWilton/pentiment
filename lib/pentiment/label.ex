defmodule Pentiment.Label do
  @moduledoc """
  A labeled span for annotating source code in diagnostics.

  Labels combine a span with a message and visual priority. They are used to
  highlight specific regions of source code and explain what's happening there.

  ## Priority

  Labels have two priority levels:

  - `:primary` - The main error location, highlighted prominently (typically red)
  - `:secondary` - Supporting context, highlighted less prominently (typically yellow)

  ## Multi-file Diagnostics

  For diagnostics that span multiple files, set the `:source` field to identify
  which file this label refers to.

  ## Examples

      # Primary label at the error site
      Label.primary(span, "expected `integer`, found `float`")

      # Secondary label showing related context
      Label.secondary(decl_span, "declared as `integer` here")

      # Label in a different file
      Label.primary(span, "error here", source: "lib/other.ex")
  """

  alias Pentiment.Spannable

  @type priority :: :primary | :secondary
  @type style :: :inline | :bracket

  @type t :: %__MODULE__{
          span: Pentiment.Span.t() | Spannable.t(),
          message: String.t() | nil,
          priority: priority(),
          style: style(),
          source: String.t() | nil
        }

  @enforce_keys [:span]
  defstruct [
    :span,
    :message,
    :source,
    priority: :primary,
    style: :inline
  ]

  @doc """
  Creates a new label.

  ## Options

  - `:message` - The annotation message (optional)
  - `:priority` - `:primary` or `:secondary` (default: `:primary`)
  - `:style` - `:inline` or `:bracket` (default: `:inline`)
  - `:source` - Source identifier for multi-file diagnostics (optional)

  ## Examples

      iex> Label.new(span, message: "error here")
      %Label{span: span, message: "error here", priority: :primary, source: nil}
  """
  @spec new(Pentiment.Span.t() | Spannable.t(), keyword()) :: t()
  def new(span, opts \\ []) do
    %__MODULE__{
      span: span,
      message: Keyword.get(opts, :message),
      priority: Keyword.get(opts, :priority, :primary),
      style: Keyword.get(opts, :style, :inline),
      source: Keyword.get(opts, :source)
    }
  end

  @doc """
  Creates a primary (error site) label.

  Primary labels are highlighted prominently and represent the main location
  of the diagnostic.

  ## Examples

      iex> Label.primary(span, "expected `integer`")
      %Label{span: span, message: "expected `integer`", priority: :primary}

      iex> Label.primary(span)
      %Label{span: span, message: nil, priority: :primary}
  """
  @spec primary(Pentiment.Span.t() | Spannable.t(), String.t() | nil, keyword()) :: t()
  def primary(span, message \\ nil, opts \\ []) do
    new(span, Keyword.merge(opts, message: message, priority: :primary))
  end

  @doc """
  Creates a secondary (context) label.

  Secondary labels provide supporting context and are highlighted less
  prominently than primary labels.

  ## Examples

      iex> Label.secondary(span, "declared here")
      %Label{span: span, message: "declared here", priority: :secondary}
  """
  @spec secondary(Pentiment.Span.t() | Spannable.t(), String.t() | nil, keyword()) :: t()
  def secondary(span, message \\ nil, opts \\ []) do
    new(span, Keyword.merge(opts, message: message, priority: :secondary))
  end

  @doc """
  Creates a bracket label that highlights a multi-line block.

  Bracket labels draw a vertical bar (`┃`) in the left margin across a range
  of lines, with a `╰── message` tail below. The span must cover the full
  line range (use `end_line` in the position span).

  ## Examples

      iex> Label.bracket(span, "property `no_stuck_states` failed")
      %Label{span: span, message: "property `no_stuck_states` failed", style: :bracket}
  """
  @spec bracket(Pentiment.Span.t() | Spannable.t(), String.t() | nil, keyword()) :: t()
  def bracket(span, message \\ nil, opts \\ []) do
    new(span, Keyword.merge(opts, message: message, priority: :primary, style: :bracket))
  end

  @doc """
  Returns true if this is a bracket label.
  """
  @spec bracket?(t()) :: boolean()
  def bracket?(%__MODULE__{style: :bracket}), do: true
  def bracket?(%__MODULE__{}), do: false

  @doc """
  Returns the resolved span as a `Pentiment.Span.t()`.

  If the label's span implements `Pentiment.Spannable`, it is converted.
  """
  @spec resolved_span(t()) :: Pentiment.Span.t()
  def resolved_span(%__MODULE__{span: %Pentiment.Span.Byte{} = span}), do: span
  def resolved_span(%__MODULE__{span: %Pentiment.Span.Position{} = span}), do: span
  def resolved_span(%__MODULE__{span: span}), do: Spannable.to_span(span)

  @doc """
  Returns true if this is a primary label.
  """
  @spec primary?(t()) :: boolean()
  def primary?(%__MODULE__{priority: :primary}), do: true
  def primary?(%__MODULE__{}), do: false

  @doc """
  Returns true if this is a secondary label.
  """
  @spec secondary?(t()) :: boolean()
  def secondary?(%__MODULE__{priority: :secondary}), do: true
  def secondary?(%__MODULE__{}), do: false
end
