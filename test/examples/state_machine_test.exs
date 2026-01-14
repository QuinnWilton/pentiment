defmodule Pentiment.Examples.StateMachineTest do
  use ExUnit.Case, async: true

  describe "StateMachine example" do
    test "valid state machine compiles successfully" do
      code = """
      defmodule TestValidStateMachine#{System.unique_integer([:positive])} do
        use Pentiment.Examples.StateMachine

        defstate :green
        defstate :yellow
        defstate :red

        deftransition :change, from: :green, to: :yellow
        deftransition :change, from: :yellow, to: :red
        deftransition :change, from: :red, to: :green
      end
      """

      assert [{module, _}] = Code.compile_string(code)

      # Test runtime API.
      assert module.states() == [:red, :yellow, :green]
      assert module.can_transition?(:green, :change)
      assert {:ok, :yellow} = module.transition(:green, :change)
      assert {:error, :invalid_transition} = module.transition(:green, :stop)
    end

    test "undefined state in 'to' raises CompileError with Pentiment formatting" do
      code = """
      defmodule TestUndefinedToState#{System.unique_integer([:positive])} do
        use Pentiment.Examples.StateMachine

        defstate :green
        defstate :yellow
        defstate :red

        deftransition :change, from: :green, to: :yello
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(code)
        end

      # Verify the error contains Pentiment formatting.
      assert error.description =~ "Transition references undefined state `yello`"
      assert error.description =~ "SM001"
      # Should suggest similar state in help text.
      assert error.description =~ "yellow"
      assert error.description =~ "change `to: :yello` to `to: :yellow`"
    end

    test "undefined state in 'from' raises CompileError" do
      code = """
      defmodule TestUndefinedFromState#{System.unique_integer([:positive])} do
        use Pentiment.Examples.StateMachine

        defstate :green

        deftransition :change, from: :geren, to: :green
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(code)
        end

      assert error.description =~ "Transition references undefined state `geren`"
      assert error.description =~ "green"
    end

    test "error shows defined states in note" do
      code = """
      defmodule TestStatesNote#{System.unique_integer([:positive])} do
        use Pentiment.Examples.StateMachine

        defstate :alpha
        defstate :beta
        defstate :gamma

        deftransition :go, from: :alpha, to: :delta
      end
      """

      error =
        assert_raise CompileError, fn ->
          Code.compile_string(code)
        end

      assert error.description =~ "defined states are: gamma, beta, alpha"
    end
  end
end
