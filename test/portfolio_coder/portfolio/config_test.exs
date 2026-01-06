defmodule PortfolioCoder.Portfolio.ConfigTest do
  use ExUnit.Case, async: false

  alias PortfolioCoder.Portfolio.Config
  alias PortfolioCoder.PortfolioFixtures

  setup do
    portfolio_path = PortfolioFixtures.setup_test_portfolio()

    # Save original env and app config
    original_env = System.get_env("PORTFOLIO_DIR")
    original_config = Application.get_env(:portfolio_coder, :portfolio_path)

    # Set test portfolio path via env var (takes precedence)
    System.put_env("PORTFOLIO_DIR", portfolio_path)
    Application.put_env(:portfolio_coder, :portfolio_path, portfolio_path)

    on_exit(fn ->
      # Restore original env and config
      if original_env do
        System.put_env("PORTFOLIO_DIR", original_env)
      else
        System.delete_env("PORTFOLIO_DIR")
      end

      if original_config do
        Application.put_env(:portfolio_coder, :portfolio_path, original_config)
      else
        Application.delete_env(:portfolio_coder, :portfolio_path)
      end

      PortfolioFixtures.cleanup_test_portfolio(portfolio_path)
    end)

    {:ok, portfolio_path: portfolio_path}
  end

  describe "portfolio_path/0" do
    test "returns the configured portfolio path", %{portfolio_path: portfolio_path} do
      assert Config.portfolio_path() == portfolio_path
    end

    test "returns default path when not configured" do
      # Must also clear the env var which takes precedence
      System.delete_env("PORTFOLIO_DIR")
      Application.delete_env(:portfolio_coder, :portfolio_path)
      default = Config.default_portfolio_path()
      # Default is unexpanded, but portfolio_path() expands it
      assert Config.portfolio_path() == Config.expand_path(default)
    end
  end

  describe "expand_path/1" do
    test "expands ~ to home directory" do
      expanded = Config.expand_path("~/test/path")
      assert String.starts_with?(expanded, "/")
      refute String.contains?(expanded, "~")
    end

    test "leaves absolute paths unchanged" do
      path = "/absolute/path/here"
      assert Config.expand_path(path) == path
    end
  end

  describe "load/0" do
    test "loads and parses config.yml", %{portfolio_path: _portfolio_path} do
      assert {:ok, config} = Config.load()
      # YAML may parse "1.0" as float 1.0
      assert config["version"] in ["1.0", 1.0]
      assert config["portfolio"]["name"] == "Test Portfolio"
    end

    test "returns error when config file missing" do
      System.put_env("PORTFOLIO_DIR", "/nonexistent/path")
      Application.put_env(:portfolio_coder, :portfolio_path, "/nonexistent/path")
      assert {:error, _reason} = Config.load()
    end
  end

  describe "scan_directories/0" do
    test "returns list of directories to scan", %{portfolio_path: portfolio_path} do
      dirs = Config.scan_directories()
      assert is_list(dirs)
      assert length(dirs) > 0
      assert Enum.all?(dirs, &is_binary/1)
      # Should include the repos directory from our test config
      assert Enum.any?(dirs, &String.contains?(&1, portfolio_path))
    end
  end

  describe "exclude_patterns/0" do
    test "returns list of exclude patterns" do
      patterns = Config.exclude_patterns()
      assert is_list(patterns)
      assert "**/node_modules/**" in patterns
      assert "**/.git/**" in patterns
    end
  end

  describe "get/2" do
    test "retrieves nested config values" do
      assert {:ok, "Test Portfolio"} = Config.get(["portfolio", "name"])
      assert {:ok, "test_user"} = Config.get(["portfolio", "owner"])
    end

    test "returns default for missing keys" do
      assert {:ok, "default_value"} = Config.get(["nonexistent", "key"], "default_value")
    end

    test "returns error for missing keys without default" do
      assert {:error, :not_found} = Config.get(["nonexistent", "key"])
    end
  end

  describe "exists?/0" do
    test "returns true when portfolio exists", %{portfolio_path: _path} do
      assert Config.exists?()
    end

    test "returns false when portfolio doesn't exist" do
      System.put_env("PORTFOLIO_DIR", "/nonexistent/path")
      Application.put_env(:portfolio_coder, :portfolio_path, "/nonexistent/path")
      refute Config.exists?()
    end
  end
end
