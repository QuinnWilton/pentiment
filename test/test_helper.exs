ExUnit.start()

# Compile example support modules (no deps)
Code.require_file("support/examples/config_validation.ex", __DIR__)
Code.require_file("support/examples/state_machine.ex", __DIR__)
Code.require_file("support/examples/guard_restriction.ex", __DIR__)

# Compile examples with optional deps (conditionally)
if Code.ensure_loaded?(NimbleParsec) do
  Code.require_file("support/examples/parser_errors.ex", __DIR__)
else
  ExUnit.configure(exclude: [:requires_nimble_parsec])
end

if Code.ensure_loaded?(:yamerl) do
  Code.require_file("support/examples/yaml_validation.ex", __DIR__)
else
  ExUnit.configure(exclude: [:requires_yamerl])
end
