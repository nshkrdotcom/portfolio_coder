defmodule PortfolioCoder.Parsers do
  @moduledoc """
  Code parsing utilities for extracting structure from source files.

  Provides language-specific parsers that extract modules, functions,
  classes, and other structural elements from source code.
  """

  alias PortfolioCoder.Parsers.Elixir, as: ElixirParser
  alias PortfolioCoder.Parsers.JavaScript
  alias PortfolioCoder.Parsers.Python

  @doc """
  Parse source code and extract structure.

  Returns a map with extracted elements like modules, functions, classes, etc.
  """
  @spec parse(String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def parse(content, :elixir), do: ElixirParser.parse(content)
  def parse(content, :python), do: Python.parse(content)
  def parse(content, :javascript), do: JavaScript.parse(content)
  def parse(content, :typescript), do: JavaScript.parse(content)
  def parse(_content, language), do: {:error, {:unsupported_language, language}}

  @doc """
  Extract function/method signatures from code.
  """
  @spec extract_signatures(String.t(), atom()) :: {:ok, [map()]} | {:error, term()}
  def extract_signatures(content, :elixir), do: ElixirParser.extract_signatures(content)
  def extract_signatures(content, :python), do: Python.extract_signatures(content)
  def extract_signatures(content, :javascript), do: JavaScript.extract_signatures(content)
  def extract_signatures(content, :typescript), do: JavaScript.extract_signatures(content)
  def extract_signatures(_content, language), do: {:error, {:unsupported_language, language}}

  @doc """
  Extract module/class definitions from code.
  """
  @spec extract_definitions(String.t(), atom()) :: {:ok, [map()]} | {:error, term()}
  def extract_definitions(content, :elixir), do: ElixirParser.extract_definitions(content)
  def extract_definitions(content, :python), do: Python.extract_definitions(content)
  def extract_definitions(content, :javascript), do: JavaScript.extract_definitions(content)
  def extract_definitions(content, :typescript), do: JavaScript.extract_definitions(content)
  def extract_definitions(_content, language), do: {:error, {:unsupported_language, language}}
end
