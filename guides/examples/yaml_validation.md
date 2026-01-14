# YAML Validation Example

This example demonstrates semantic validation of parsed YAML files using yamerl.

> **Requires:** `{:yamerl, "~> 0.10"}` as a test dependency

## Use Case

You're validating configuration files and want to:

- Parse YAML with position tracking
- Validate field types and known keys
- Show errors at the exact field location

## Example Error Output

![YAML validation error](https://raw.githubusercontent.com/QuinnWilton/pentiment/main/images/yaml_validation.png)

## Usage

```elixir
case Pentiment.Examples.YamlValidation.validate("deploy.yml") do
  {:ok, config} ->
    deploy(config)

  {:error, formatted_errors} ->
    IO.puts(formatted_errors)
end
```

## Implementation

The full implementation is in `test/support/examples/yaml_validation.ex`.

### Key Points

**1. Parse with position tracking**

yamerl's `detailed_constr: true` option provides position information:

```elixir
defp parse_with_positions(content) do
  opts = [
    detailed_constr: true,
    str_node_as_binary: true
  ]

  [doc] = :yamerl_constr.string(String.to_charlist(content), opts)
  doc = unwrap_doc(doc)
  {data, positions} = extract_with_positions(doc, [])
  {:ok, data, positions}
end
```

**2. Extract data and build position map**

yamerl returns tuples like `{:yamerl_str, :yamerl_node_str, tag, [line: 1, column: 5], "value"}`:

```elixir
defp extract_with_positions({:yamerl_map, _, _tag, _pos, pairs}, path) do
  Enum.reduce(pairs, {%{}, %{}}, fn
    {{:yamerl_str, _, _tag2, key_pos, key}, value_node}, {map_acc, pos_acc} ->
      key_str = to_string(key)
      key_path = path ++ [key_str]
      key_span = span_from_yamerl_pos(key_pos)

      {value, value_positions} = extract_with_positions(value_node, key_path)

      new_pos =
        pos_acc
        |> Map.put(key_path, %{key_span: key_span, value_span: get_value_span(value_node)})
        |> Map.merge(value_positions)

      {Map.put(map_acc, key_str, value), new_pos}
  end)
end

defp span_from_yamerl_pos(pos) when is_list(pos) do
  line = Keyword.get(pos, :line, 1)
  col = Keyword.get(pos, :column, 1)
  Pentiment.Span.position(line, col)
end
```

**3. Validate with position lookup**

```elixir
defp validate_field_types(errors, service, positions, path) do
  case Map.get(service, "replicas") do
    nil -> errors
    value when is_integer(value) -> errors
    value ->
      field_path = path ++ ["replicas"]
      %{value_span: span} = Map.get(positions, field_path)

      [%{
        message: "Field `replicas` has wrong type",
        span: span,
        severity: :error,
        code: "SCHEMA001",
        label: "expected integer, found #{type_name(value)} #{inspect(value)}",
        help: "use a number like `replicas: 3`"
      } | errors]
  end
end
```

**4. Format all errors together**

```elixir
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
  |> Pentiment.format_all(source, colors: false)
end
```

## Key Techniques

- **yamerl `detailed_constr`**: Returns position metadata with each node
- **Position map**: Build a map from field paths to spans during parsing
- **Validation separation**: Parse first, validate second, format at the end
- **`Pentiment.format_all/3`**: Format multiple diagnostics together

## Testing

```elixir
test "valid YAML validates successfully" do
  yaml = """
  service:
    name: my-app
    replicas: 3
  """

  assert {:ok, data} = Pentiment.Examples.YamlValidation.validate_string("test.yml", yaml)
  assert get_in(data, ["service", "replicas"]) == 3
end

test "wrong type produces error" do
  yaml = """
  service:
    replicas: "three"
  """

  {:error, formatted} = Pentiment.Examples.YamlValidation.validate_string("test.yml", yaml)
  assert formatted =~ "Field `replicas` has wrong type"
  assert formatted =~ "expected integer"
end
```
