defmodule Pentiment.Examples.StateMachine do
  @moduledoc """
  Example: State machine DSL with multi-span error messages.

  This example demonstrates how to use Pentiment to show errors that reference
  multiple related locations in the code. Key patterns shown:

  - Tracking definition locations for later reference
  - Using secondary labels to show related context
  - Using `__before_compile__` for deferred validation

  ## Usage

      defmodule TrafficLight do
        use Pentiment.Examples.StateMachine

        defstate :green
        defstate :yellow
        defstate :red

        deftransition :change, from: :green, to: :yellow
        deftransition :change, from: :yellow, to: :red
        deftransition :change, from: :red, to: :green
      end

  ## Error Output

  If you reference an undefined state:

      deftransition :change, from: :red, to: :gren  # typo

  You'll get a multi-span error:

      error[SM001]: Transition references undefined state `gren`
         ╭─[lib/traffic_light.ex:5:14]
         │
       5 │   defstate :green
         •              ──┬──
         •                ╰── did you mean this state?
         │
         ╭─[lib/traffic_light.ex:11:42]
         │
      11 │   deftransition :change, from: :red, to: :gren
         •                                          ──┬──
         •                                            ╰── undefined state
         │
         ╰─
            help: change `to: :gren` to `to: :green`
            note: defined states are: green, yellow, red
  """

  defmacro __using__(_opts) do
    quote do
      import Pentiment.Examples.StateMachine, only: [defstate: 1, deftransition: 2]
      Module.register_attribute(__MODULE__, :sm_states, accumulate: true)
      Module.register_attribute(__MODULE__, :sm_transitions, accumulate: true)
      @before_compile Pentiment.Examples.StateMachine
    end
  end

  @doc """
  Defines a state in the state machine.
  """
  defmacro defstate(name) do
    caller = __CALLER__
    name_str = Atom.to_string(name)

    quote do
      @sm_states {
        unquote(name),
        %{
          file: unquote(caller.file),
          line: unquote(caller.line),
          # Store the name for search span resolution.
          name_pattern: unquote(":#{name_str}")
        }
      }
    end
  end

  @doc """
  Defines a transition between states.
  """
  defmacro deftransition(event, opts) do
    caller = __CALLER__
    from = Keyword.fetch!(opts, :from)
    to = Keyword.fetch!(opts, :to)
    from_str = Atom.to_string(from)
    to_str = Atom.to_string(to)

    quote do
      @sm_transitions {
        unquote(event),
        unquote(from),
        unquote(to),
        %{
          file: unquote(caller.file),
          line: unquote(caller.line),
          # Store patterns for search span resolution (just the atom, not the key).
          from_pattern: unquote(":#{from_str}"),
          to_pattern: unquote(":#{to_str}")
        }
      }
    end
  end

  defmacro __before_compile__(env) do
    states = Module.get_attribute(env.module, :sm_states) || []
    transitions = Module.get_attribute(env.module, :sm_transitions) || []

    state_names = Enum.map(states, fn {name, _meta} -> name end)

    # Find all references to undefined states.
    errors =
      transitions
      |> Enum.flat_map(fn {_event, from, to, trans_meta} ->
        undefined_refs = []

        undefined_refs =
          if from not in state_names do
            [{:from, from, trans_meta} | undefined_refs]
          else
            undefined_refs
          end

        undefined_refs =
          if to not in state_names do
            [{:to, to, trans_meta} | undefined_refs]
          else
            undefined_refs
          end

        undefined_refs
      end)

    if errors != [] do
      # Build reports for each error.
      reports =
        Enum.map(errors, fn {field, undefined_state, trans_meta} ->
          build_undefined_state_error(field, undefined_state, trans_meta, states, env.file)
        end)

      # Format all errors together.
      source = Pentiment.Elixir.source_from_env(env)
      formatted = Pentiment.format_all(reports, source, colors: false)

      raise CompileError, description: formatted
    end

    # Generate the runtime API.
    state_list = Enum.map(states, fn {name, _} -> name end)

    transition_list =
      Enum.map(transitions, fn {event, from, to, _} ->
        {event, from, to}
      end)

    quote do
      def states, do: unquote(state_list)
      def transitions, do: unquote(Macro.escape(transition_list))

      def can_transition?(from, event) do
        Enum.any?(transitions(), fn {e, f, _} -> e == event and f == from end)
      end

      def transition(from, event) do
        case Enum.find(transitions(), fn {e, f, _} -> e == event and f == from end) do
          {_, _, to} -> {:ok, to}
          nil -> {:error, :invalid_transition}
        end
      end
    end
  end

  defp build_undefined_state_error(field, undefined_state, trans_meta, states, _file) do
    # Find similar state for suggestion.
    state_names = Enum.map(states, fn {name, _} -> name end)
    similar = find_similar(undefined_state, state_names)

    # Build the transition span (primary label) using a search span.
    # Use the stored pattern for the field (from_pattern or to_pattern).
    pattern = Map.get(trans_meta, :"#{field}_pattern", "#{field}: :#{undefined_state}")

    trans_span =
      Pentiment.Span.search(
        line: trans_meta.line,
        pattern: pattern
      )

    # Build the report with primary label.
    report =
      Pentiment.Report.error("Transition references undefined state `#{undefined_state}`")
      |> Pentiment.Report.with_code("SM001")
      |> Pentiment.Report.with_source(trans_meta.file)
      |> Pentiment.Report.with_label(Pentiment.Label.primary(trans_span, "undefined state"))

    # Add secondary label pointing to similar state definition.
    report =
      if similar do
        {_similar_name, similar_meta} = Enum.find(states, fn {n, _} -> n == similar end)

        # Use search span to find the state definition.
        def_span =
          Pentiment.Span.search(
            line: similar_meta.line,
            pattern: similar_meta.name_pattern
          )

        report
        |> Pentiment.Report.with_label(
          Pentiment.Label.secondary(def_span, "did you mean this state?",
            source: similar_meta.file
          )
        )
        |> Pentiment.Report.with_help(
          "change `#{field}: :#{undefined_state}` to `#{field}: :#{similar}`"
        )
      else
        report
      end

    # Add note with all valid states.
    Pentiment.Report.with_note(report, "defined states are: #{Enum.join(state_names, ", ")}")
  end

  defp find_similar(input, candidates) do
    input_str = to_string(input)

    candidates
    |> Enum.map(&{&1, String.jaro_distance(input_str, to_string(&1))})
    |> Enum.filter(fn {_, score} -> score > 0.7 end)
    |> Enum.max_by(fn {_, score} -> score end, fn -> nil end)
    |> case do
      {match, _} -> match
      nil -> nil
    end
  end
end
