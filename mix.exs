defmodule Pentiment.MixProject do
  use Mix.Project

  def project do
    [
      app: :pentiment,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
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

  defp deps do
    [
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      # nimble_parsec is used by ex_doc's deps in dev, and our parser example in test.
      {:nimble_parsec, "~> 1.0", only: [:dev, :test], optional: true},
      {:yamerl, "~> 0.10", only: :test, optional: true}
    ]
  end

  defp docs do
    [
      main: "readme",
      assets: %{"guides/images" => "images"},
      extras: [
        "README.md",
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
