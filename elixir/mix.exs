defmodule SeleniumCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :selenium_core,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Selenium WebDriver for Elixir — a thin wrapper over the shared Aether " <>
          "Selenium NIF (the Erlang `selenium_nif` app) on the BEAM."
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps, do: []
end
