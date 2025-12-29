defmodule PortfolioCoder.ToolsTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Tools

  describe "list_tools/0" do
    test "returns list of available tools" do
      tools = Tools.list_tools()

      assert is_list(tools)
      assert length(tools) == 4

      tool_names = Enum.map(tools, & &1.name)
      assert "search_code" in tool_names
      assert "read_file" in tool_names
      assert "list_files" in tool_names
      assert "analyze_code" in tool_names
    end

    test "each tool has required fields" do
      tools = Tools.list_tools()

      for tool <- tools do
        assert Map.has_key?(tool, :name)
        assert Map.has_key?(tool, :description)
        assert Map.has_key?(tool, :parameters)
      end
    end
  end

  describe "execute/2" do
    test "returns error for unknown tool" do
      result = Tools.execute("unknown_tool", %{})
      assert {:error, {:unknown_tool, "unknown_tool"}} = result
    end

    test "delegates to read_file tool" do
      tmp_file = Path.join(System.tmp_dir!(), "test_execute_#{:rand.uniform(10000)}.txt")
      File.write!(tmp_file, "test content")

      on_exit(fn -> File.rm(tmp_file) end)

      {:ok, result} = Tools.execute("read_file", %{"path" => tmp_file})
      assert result.path == tmp_file
    end

    test "delegates to list_files tool" do
      {:ok, result} = Tools.execute("list_files", %{"path" => System.tmp_dir!()})
      assert is_list(result.files)
    end
  end
end
