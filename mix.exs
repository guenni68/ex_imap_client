defmodule ExImapClient.MixProject do
  use Mix.Project

  @version "0.2.0"
  @url "https://github.com/guenni68/ex_imap_client.git"

  def project do
    [
      app: :ex_imap_client,
      name: "ExImapClient",
      version: @version,
      elixir: "~> 1.14",
      description: "A library for communicating with an IMAP server",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      docs: [
        api_reference: false,
        main: ExImapClient,
        extras: ["README.md"]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :ssl],
      mod: {ExImapClient.Application, []}
    ]
  end

  defp package() do
    %{
      licenses: ["Apache-2.0"],
      maintainers: ["Guenther Schmidt"],
      links: %{"GitHub" => @url}
    }
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:parser_builder, "~> 1.3"},
      {:gen_state_machine, "~> 3.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
