defmodule Pentiment.Highlighter do
  @moduledoc """
  Behaviour for source-context syntax highlighters.

  A highlighter turns full source content into per-line styled segments
  that the formatter interleaves with its own frame decoration. The
  default implementation is `Pentiment.Highlighter.Makeup`, active only
  when the optional makeup dependencies are present; pass a custom module
  via the `:highlighter` format option to substitute your own.

  Highlighting is purely cosmetic: the formatter verifies each line's
  segments against the raw source line and falls back to plain text on
  any mismatch, so a buggy highlighter can never corrupt pointer
  alignment or change the visible characters.
  """

  @typedoc """
  One styled run of text: an ANSI escape prefix (`nil` for unstyled) and
  the text it applies to. The text never contains newlines.
  """
  @type segment :: {ansi :: String.t() | nil, text :: String.t()}

  @typedoc """
  Styled segments keyed by 1-indexed source line.

  Contract: for every line present, joining the segment texts must
  reproduce that source line exactly. Lines may be absent (rendered
  plain). The formatter enforces the contract per line and renders the
  raw line when it does not hold.
  """
  @type line_map :: %{pos_integer() => [segment()]}

  @doc """
  Highlights the given source content.

  Returns `{:ok, line_map}` on success, or `:error` when the language is
  unsupported or the highlighter cannot run (for example, when an
  optional lexer dependency is not available). `:error` means the source
  renders unhighlighted; it is never a failure of the diagnostic itself.
  """
  @callback highlight(content :: String.t(), language :: atom()) :: {:ok, line_map()} | :error
end
