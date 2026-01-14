defmodule Pentiment.Examples.YamlValidationTest do
  use ExUnit.Case, async: true

  @moduletag :requires_yamerl

  describe "YamlValidation example" do
    test "valid YAML validates successfully" do
      yaml = """
      service:
        name: my-app
        replicas: 3
        ports:
          - 8080
          - 8081
        environment:
          LOG_LEVEL: debug
      """

      assert {:ok, data} = Pentiment.Examples.YamlValidation.validate_string("test.yml", yaml)
      assert get_in(data, ["service", "name"]) == "my-app"
      assert get_in(data, ["service", "replicas"]) == 3
    end

    test "wrong type for replicas produces error" do
      yaml = """
      service:
        name: my-app
        replicas: "three"
      """

      {:error, formatted} = Pentiment.Examples.YamlValidation.validate_string("test.yml", yaml)

      assert formatted =~ "Field `replicas` has wrong type"
      assert formatted =~ "SCHEMA001"
      assert formatted =~ "expected integer"
      assert formatted =~ ~s(string "three")
      assert formatted =~ "use a number like `replicas: 3`"
    end

    test "unknown field produces warning" do
      yaml = """
      service:
        name: my-app
        environmnet:
          LOG_LEVEL: debug
      """

      {:error, formatted} = Pentiment.Examples.YamlValidation.validate_string("test.yml", yaml)

      assert formatted =~ "Unknown field `environmnet`"
      assert formatted =~ "SCHEMA002"
      assert formatted =~ "unknown field"
      assert formatted =~ "did you mean `environment`?"
    end

    test "multiple errors are reported together" do
      yaml = """
      service:
        naem: my-app
        replicas: "five"
        environmnet:
          LOG_LEVEL: debug
      """

      {:error, formatted} = Pentiment.Examples.YamlValidation.validate_string("test.yml", yaml)

      # Should have multiple errors.
      assert formatted =~ "replicas"
      assert formatted =~ "naem"
      assert formatted =~ "environmnet"
    end
  end
end
