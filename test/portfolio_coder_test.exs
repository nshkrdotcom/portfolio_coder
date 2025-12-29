defmodule PortfolioCoderTest do
  use ExUnit.Case, async: true
  doctest PortfolioCoder

  describe "supported_languages/0" do
    test "returns list of supported languages" do
      languages = PortfolioCoder.supported_languages()
      assert is_list(languages)
      assert :elixir in languages
      assert :python in languages
      assert :javascript in languages
    end
  end
end
