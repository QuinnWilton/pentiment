defmodule Pentiment.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/QuinnWilton/pentiment"

  def project do
    [
      app: :pentiment,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: "Beautiful, compiler-style diagnostic messages for Elixir",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      test_ignore_filters: [~r"/support/"],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp deps do
    [
      # Optional lexers for syntax highlighting: consumers that want
      # highlighted diagnostics add these to their own deps; without
      # them, diagnostics render unhighlighted.
      {:makeup, "~> 1.2", optional: true},
      {:makeup_elixir, "~> 1.0", optional: true},
      {:makeup_erlang, "~> 1.0", optional: true},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      # nimble_parsec backs the optional makeup lexers, ex_doc's deps in
      # dev, and our parser example in test. It cannot be :only-restricted
      # because makeup requires it in every environment.
      {:nimble_parsec, "~> 1.0", optional: true},
      {:yamerl, "~> 0.10", only: :test, optional: true}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      assets: %{"images" => "images"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/examples/overview.md",
        "guides/examples/config_validation.md",
        "guides/examples/state_machine.md",
        "guides/examples/guard_restriction.md",
        "guides/examples/parser_errors.md",
        "guides/examples/yaml_validation.md"
      ],
      groups_for_extras: [
        Examples: ~r/guides\/examples\/.*/
      ]
    ]
  end
end
