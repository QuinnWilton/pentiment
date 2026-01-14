defmodule Pentiment.Examples.YamlValidation do
  @moduledoc """
  Example: Semantic validation of parsed YAML files using yamerl.

  This example demonstrates how to use Pentiment with yamerl to provide
  rich error messages for YAML configuration validation. Key patterns shown:

  - Using yamerl's detailed token info for position tracking
  - Building a position map during parsing
  - Semantic validation with field-level error locations

  **Requires optional dependency:** `{:yamerl, "~> 0.10"}`

  ## Usage

      case Pentiment.Examples.YamlValidation.validate("deploy.yml") do
        {:ok, config} -> deploy(config)
        {:error, formatted_errors} -> IO.puts(formatted_errors)
      end

  ## Error Output

      error[SCHEMA001]: Field `replicas` has wrong type
         ╭─[deploy.yml:4:13]
         │
       4 │   replicas: "three"
         •             ───┬────
         •                ╰── expected integer, found string "three"
         │
         ╰─
            help: use a number like `replicas: 3`
  """

  @known_service_fields ~w(name replicas ports environment image command)

  @doc """
  Parses and validates a deploy.yml file.

  Returns `{:ok, data}` if valid, or `{:error, formatted_message}` with
  Pentiment-formatted errors if validation fails.
  """
  @spec validate(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def validate(path) do
    content = File.read!(path)
    source = Pentiment.Source.from_string(path, content)

    case parse_with_positions(content) do
      {:ok, data, positions} ->
        errors = validate_service(data, positions, [])

        case errors do
          [] -> {:ok, data}
          _ -> {:error, format_errors(errors, path, source)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates a YAML string directly (useful for testing).
  """
  @spec validate_string(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def validate_string(source_name, content) do
    source = Pentiment.Source.from_string(source_name, content)

    case parse_with_positions(content) do
      {:ok, data, positions} ->
        errors = validate_service(data, positions, [])

        case errors do
          [] -> {:ok, data}
          _ -> {:error, format_errors(errors, source_name, source)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Parse YAML and extract position map for each key/value.
  defp parse_with_positions(content) do
    # Configure yamerl to return detailed token info.
    opts = [
      detailed_constr: true,
      str_node_as_binary: true
    ]

    try do
      [doc] = :yamerl_constr.string(String.to_charlist(content), opts)
      # yamerl wraps in :yamerl_doc - unwrap it.
      doc = unwrap_doc(doc)
      {data, positions} = extract_with_positions(doc, [])
      {:ok, data, positions}
    catch
      {:yamerl_exception, [{:yamerl_parsing_error, _, _, msg, line, col, _, _} | _]} ->
        {:error, "YAML parse error at line #{line}, column #{col}: #{msg}"}

      :throw, {:yamerl_exception, errors} ->
        [{:yamerl_parsing_error, _, _, msg, line, col, _, _} | _] = errors
        {:error, "YAML parse error at line #{line}, column #{col}: #{msg}"}
    end
  end

  # Unwrap yamerl_doc wrapper.
  defp unwrap_doc({:yamerl_doc, content}), do: content
  defp unwrap_doc(content), do: content

  # Recursively extract data and build position map.
  # yamerl detailed_constr returns: {:yamerl_map, :yamerl_node_map, tag, pos, pairs}
  # where pos is a keyword list like [line: 1, column: 1]
  defp extract_with_positions({:yamerl_map, _, _tag, _pos, pairs}, path) do
    {map, positions} =
      Enum.reduce(pairs, {%{}, %{}}, fn
        {{:yamerl_str, _, _tag2, key_pos, key}, value_node}, {map_acc, pos_acc} ->
          key_str = to_string(key)
          key_path = path ++ [key_str]
          key_span = span_from_yamerl_pos(key_pos)

          {value, value_positions} = extract_with_positions(value_node, key_path)

          new_map = Map.put(map_acc, key_str, value)

          new_pos =
            pos_acc
            |> Map.put(key_path, %{key_span: key_span, value_span: get_value_span(value_node)})
            |> Map.merge(value_positions)

          {new_map, new_pos}

        # Handle other key types if needed.
        _, acc ->
          acc
      end)

    {map, positions}
  end

  defp extract_with_positions({:yamerl_seq, _, _tag, _pos, items, _count}, path) do
    {list, positions} =
      items
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {item, idx}, {list_acc, pos_acc} ->
        item_path = path ++ [idx]
        {value, item_positions} = extract_with_positions(item, item_path)
        {list_acc ++ [value], Map.merge(pos_acc, item_positions)}
      end)

    {list, positions}
  end

  # Also handle seq without count (older yamerl format)
  defp extract_with_positions({:yamerl_seq, _, _tag, _pos, items}, path) do
    {list, positions} =
      items
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {item, idx}, {list_acc, pos_acc} ->
        item_path = path ++ [idx]
        {value, item_positions} = extract_with_positions(item, item_path)
        {list_acc ++ [value], Map.merge(pos_acc, item_positions)}
      end)

    {list, positions}
  end

  defp extract_with_positions({:yamerl_str, _, _tag, _pos, value}, _path) do
    {to_string(value), %{}}
  end

  defp extract_with_positions({:yamerl_int, _, _tag, _pos, value}, _path) do
    {value, %{}}
  end

  defp extract_with_positions({:yamerl_null, _, _tag, _pos}, _path) do
    {nil, %{}}
  end

  defp extract_with_positions(other, _path) do
    # Fallback for unexpected types.
    {other, %{}}
  end

  # Convert yamerl position keyword list to Pentiment span.
  defp span_from_yamerl_pos(pos) when is_list(pos) do
    line = Keyword.get(pos, :line, 1)
    col = Keyword.get(pos, :column, 1)
    Pentiment.Span.position(line, col)
  end

  defp span_from_yamerl_pos(_), do: Pentiment.Span.position(1, 1)

  defp get_value_span({_, _, _tag, pos, _}), do: span_from_yamerl_pos(pos)
  defp get_value_span({_, _, _tag, pos, _, _}), do: span_from_yamerl_pos(pos)
  defp get_value_span(_), do: Pentiment.Span.position(1, 1)

  # Validation logic.
  defp validate_service(data, positions, errors) do
    service = Map.get(data, "service", %{})
    service_path = ["service"]

    errors
    |> validate_field_types(service, positions, service_path)
    |> validate_unknown_fields(service, positions, service_path)
  end

  defp validate_field_types(errors, service, positions, path) do
    # Check replicas is an integer.
    case Map.get(service, "replicas") do
      nil ->
        errors

      value when is_integer(value) ->
        errors

      value ->
        field_path = path ++ ["replicas"]

        # Use search span to find the actual value in source.
        span =
          case Map.get(positions, field_path) do
            %{value_span: %{start_line: line, start_column: col}} ->
              # Search for the quoted string value.
              Pentiment.Span.search(line: line, pattern: inspect(value), after_column: col)

            _ ->
              Pentiment.Span.position(1, 1)
          end

        [
          %{
            path: field_path,
            message: "Field `replicas` has wrong type",
            span: span,
            severity: :error,
            code: "SCHEMA001",
            label: "expected integer, found #{type_name(value)} #{inspect(value)}",
            help: "use a number like `replicas: 3`"
          }
          | errors
        ]
    end
  end

  defp validate_unknown_fields(errors, service, positions, path) do
    service
    |> Map.keys()
    |> Enum.reject(&(&1 in @known_service_fields))
    |> Enum.reduce(errors, fn unknown_key, acc ->
      field_path = path ++ [unknown_key]

      # Use search span to find the key name in source.
      span =
        case Map.get(positions, field_path) do
          %{key_span: %{start_line: line, start_column: col}} ->
            Pentiment.Span.search(line: line, pattern: unknown_key, after_column: col)

          _ ->
            Pentiment.Span.position(1, 1)
        end

      similar = find_similar(unknown_key, @known_service_fields)

      [
        %{
          path: field_path,
          message: "Unknown field `#{unknown_key}`",
          span: span,
          severity: :warning,
          code: "SCHEMA002",
          label: "unknown field",
          help: if(similar, do: "did you mean `#{similar}`?", else: nil)
        }
        | acc
      ]
    end)
  end

  defp format_errors(errors, path, source) do
    errors
    |> Enum.reverse()
    |> Enum.map(fn err ->
      report =
        Pentiment.Report.build(err.severity, err.message)
        |> Pentiment.Report.with_code(err.code)
        |> Pentiment.Report.with_source(path)
        |> Pentiment.Report.with_label(Pentiment.Label.primary(err.span, err.label))

      if err.help do
        Pentiment.Report.with_help(report, err.help)
      else
        report
      end
    end)
    |> Pentiment.format_all(source)
  end

  defp type_name(v) when is_binary(v), do: "string"
  defp type_name(v) when is_integer(v), do: "integer"
  defp type_name(v) when is_float(v), do: "float"
  defp type_name(v) when is_list(v), do: "list"
  defp type_name(v) when is_map(v), do: "map"
  defp type_name(_), do: "unknown"

  defp find_similar(input, candidates) do
    candidates
    |> Enum.map(&{&1, String.jaro_distance(input, &1)})
    |> Enum.filter(fn {_, score} -> score > 0.7 end)
    |> Enum.max_by(fn {_, score} -> score end, fn -> nil end)
    |> case do
      {match, _} -> match
      nil -> nil
    end
  end
end
