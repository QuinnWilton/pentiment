defmodule Pentiment.Source do
  @moduledoc """
  Represents a source of text that diagnostics can reference.

  Sources provide the content needed to display source code context in
  diagnostic output. There are three ways to create a source:

  ## Source Types

  ### `from_file/1` - File on disk

  Reads content from a file path. The source name is the file path.

      source = Pentiment.Source.from_file("lib/my_app.ex")

  ### `from_string/2` - In-memory content

  Creates a source from a string with a display name. Useful for code that
  isn't on disk (user input, test fixtures, generated code).

      source = Pentiment.Source.from_string("<stdin>", user_input)
      source = Pentiment.Source.from_string("generated.ex", generated_code)

  ### `named/1` - Deferred content

  Creates a source with just a name, no content. Content is provided later
  when formatting. Useful when accumulating diagnostics and deferring file reads.

      source = Pentiment.Source.named("lib/app.ex")
      # Later, when formatting:
      Pentiment.format(report, %{"lib/app.ex" => File.read!("lib/app.ex")})

  ## Accessing Content

  Use `lines/1` to get the source as a list of lines (for rendering), and
  `content/1` to get the raw string content.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          content: String.t() | nil,
          lines: [String.t()] | nil
        }

  @enforce_keys [:name]
  defstruct [:name, :content, :lines]

  @doc """
  Creates a source from a file path.

  Reads the file content immediately. Raises if the file cannot be read.

  ## Examples

      iex> source = Pentiment.Source.from_file("lib/my_app.ex")
      %Pentiment.Source{name: "lib/my_app.ex", content: "..."}
  """
  @spec from_file(Path.t()) :: t()
  def from_file(path) when is_binary(path) do
    content = File.read!(path)
    lines = String.split(content, "\n")

    %__MODULE__{
      name: path,
      content: content,
      lines: lines
    }
  end

  @doc """
  Creates a source from a string with a display name.

  Use this for content that isn't on disk, like user input or generated code.

  ## Examples

      iex> source = Pentiment.Source.from_string("<stdin>", "x = 1 + 2")
      %Pentiment.Source{name: "<stdin>", content: "x = 1 + 2"}
  """
  @spec from_string(String.t(), String.t()) :: t()
  def from_string(name, content) when is_binary(name) and is_binary(content) do
    lines = String.split(content, "\n")

    %__MODULE__{
      name: name,
      content: content,
      lines: lines
    }
  end

  @doc """
  Creates a named source without content.

  The content must be provided later when formatting the diagnostic.
  This is useful when you want to defer file reads or when the content
  comes from an external source.

  ## Examples

      iex> source = Pentiment.Source.named("lib/app.ex")
      %Pentiment.Source{name: "lib/app.ex", content: nil}
  """
  @spec named(String.t()) :: t()
  def named(name) when is_binary(name) do
    %__MODULE__{name: name, content: nil, lines: nil}
  end

  @doc """
  Returns the source content as a list of lines.

  Lines are 1-indexed when accessed (line 1 is at index 0).
  Returns `nil` if no content is available.

  ## Examples

      iex> source = Pentiment.Source.from_string("test", "line1\\nline2\\nline3")
      iex> Pentiment.Source.lines(source)
      ["line1", "line2", "line3"]
  """
  @spec lines(t()) :: [String.t()] | nil
  def lines(%__MODULE__{lines: lines}), do: lines

  @doc """
  Returns the raw string content of the source.

  Returns `nil` if no content is available.
  """
  @spec content(t()) :: String.t() | nil
  def content(%__MODULE__{content: content}), do: content

  @doc """
  Returns the source name (file path or display name).
  """
  @spec name(t()) :: String.t()
  def name(%__MODULE__{name: name}), do: name

  @doc """
  Returns a specific line from the source (1-indexed).

  Returns `nil` if the line doesn't exist or content is not available.

  ## Examples

      iex> source = Pentiment.Source.from_string("test", "line1\\nline2\\nline3")
      iex> Pentiment.Source.line(source, 2)
      "line2"

      iex> Pentiment.Source.line(source, 100)
      nil
  """
  @spec line(t(), pos_integer()) :: String.t() | nil
  def line(%__MODULE__{lines: nil}, _line_num), do: nil

  def line(%__MODULE__{lines: lines}, line_num)
      when is_integer(line_num) and line_num >= 1 do
    Enum.at(lines, line_num - 1)
  end

  @doc """
  Returns a range of lines from the source (1-indexed, inclusive).

  Returns an empty list if content is not available.

  ## Examples

      iex> source = Pentiment.Source.from_string("test", "a\\nb\\nc\\nd\\ne")
      iex> Pentiment.Source.line_range(source, 2, 4)
      [{2, "b"}, {3, "c"}, {4, "d"}]
  """
  @spec line_range(t(), pos_integer(), pos_integer()) :: [{pos_integer(), String.t()}]
  def line_range(%__MODULE__{lines: nil}, _start_line, _end_line), do: []

  def line_range(%__MODULE__{lines: lines}, start_line, end_line)
      when is_integer(start_line) and start_line >= 1 and
             is_integer(end_line) and end_line >= start_line do
    start_line..end_line
    |> Enum.map(fn line_num ->
      case Enum.at(lines, line_num - 1) do
        nil -> nil
        content -> {line_num, content}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns true if the source has content available.
  """
  @spec has_content?(t()) :: boolean()
  def has_content?(%__MODULE__{content: nil}), do: false
  def has_content?(%__MODULE__{}), do: true

  @doc """
  Returns the total number of lines, or nil if content is not available.
  """
  @spec line_count(t()) :: non_neg_integer() | nil
  def line_count(%__MODULE__{lines: nil}), do: nil
  def line_count(%__MODULE__{lines: lines}), do: length(lines)

  @doc """
  Converts a byte offset to a line and column position.

  Returns `{line, column}` where both are 1-indexed, or `nil` if the offset
  is out of bounds or no content is available.

  ## Examples

      iex> source = Pentiment.Source.from_string("test", "hello\\nworld")
      iex> Pentiment.Source.byte_to_position(source, 0)
      {1, 1}

      iex> source = Pentiment.Source.from_string("test", "hello\\nworld")
      iex> Pentiment.Source.byte_to_position(source, 6)
      {2, 1}

      iex> source = Pentiment.Source.from_string("test", "hello\\nworld")
      iex> Pentiment.Source.byte_to_position(source, 100)
      nil
  """
  @spec byte_to_position(t(), non_neg_integer()) :: {pos_integer(), pos_integer()} | nil
  def byte_to_position(%__MODULE__{content: nil}, _offset), do: nil

  def byte_to_position(%__MODULE__{}, offset) when not is_integer(offset) or offset < 0, do: nil

  def byte_to_position(%__MODULE__{content: content}, offset) do
    byte_size = byte_size(content)

    if offset > byte_size do
      nil
    else
      compute_position(content, offset, 1, 1)
    end
  end

  # Walks through content byte-by-byte, tracking line and column.
  defp compute_position(_content, 0, line, col), do: {line, col}

  defp compute_position(<<>>, _offset, _line, _col), do: nil

  defp compute_position(<<?\n, rest::binary>>, offset, line, _col) do
    compute_position(rest, offset - 1, line + 1, 1)
  end

  defp compute_position(<<char::utf8, rest::binary>>, offset, line, col) do
    # For multi-byte UTF-8 characters, we need to count bytes not codepoints.
    char_bytes = byte_size(<<char::utf8>>)

    if offset < char_bytes do
      # Offset is in the middle of a multi-byte character; return current position.
      {line, col}
    else
      compute_position(rest, offset - char_bytes, line, col + 1)
    end
  end

  defp compute_position(<<_byte, rest::binary>>, offset, line, col) do
    # Fallback for invalid UTF-8 sequences; treat as single byte.
    compute_position(rest, offset - 1, line, col + 1)
  end
end
