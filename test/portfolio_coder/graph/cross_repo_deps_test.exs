defmodule PortfolioCoder.Graph.CrossRepoDepsTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Graph.CrossRepoDeps

  @repos [
    %{
      name: "app_core",
      dependencies: ["phoenix", "ecto"],
      dev_dependencies: ["ex_doc", "dialyxir"]
    },
    %{
      name: "app_web",
      dependencies: ["app_core", "phoenix_live_view"],
      dev_dependencies: ["credo"]
    },
    %{
      name: "app_api",
      dependencies: ["app_core", "phoenix", "jason"],
      dev_dependencies: []
    }
  ]

  describe "build_cross_repo_graph/1" do
    test "builds graph from multiple repos" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      assert is_map(graph)
      assert Map.has_key?(graph, :nodes)
      assert Map.has_key?(graph, :edges)
    end

    test "includes all repos as nodes" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      node_names = Enum.map(graph.nodes, & &1.id)
      assert "app_core" in node_names
      assert "app_web" in node_names
      assert "app_api" in node_names
    end

    test "creates edges for dependencies" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      # app_web depends on app_core
      edge =
        Enum.find(graph.edges, fn e ->
          e.from == "app_web" and e.to == "app_core"
        end)

      assert edge != nil
    end
  end

  describe "impact_analysis/2" do
    test "finds repos affected by changes" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      impact = CrossRepoDeps.impact_analysis(graph, "app_core")

      # Both app_web and app_api depend on app_core
      affected_names = Enum.map(impact.directly_affected, & &1.name)
      assert "app_web" in affected_names
      assert "app_api" in affected_names
    end

    test "returns empty for leaf repos" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      impact = CrossRepoDeps.impact_analysis(graph, "app_web")

      assert impact.directly_affected == []
    end

    test "calculates risk level" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      impact = CrossRepoDeps.impact_analysis(graph, "app_core")

      assert impact.risk_level in [:low, :medium, :high, :critical]
    end
  end

  describe "find_shared_dependencies/1" do
    test "identifies dependencies used by multiple repos" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      shared = CrossRepoDeps.find_shared_dependencies(graph)

      # phoenix is used by both app_core and app_api
      phoenix = Enum.find(shared, &(&1.dependency == "phoenix"))
      assert phoenix != nil
      assert length(phoenix.used_by) >= 2
    end

    test "returns usage count for each shared dependency" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      shared = CrossRepoDeps.find_shared_dependencies(graph)

      Enum.each(shared, fn dep ->
        assert is_binary(dep.dependency)
        assert is_list(dep.used_by)
        assert dep.count == length(dep.used_by)
      end)
    end
  end

  describe "find_dependency_versions/1" do
    test "extracts version info when available" do
      repos_with_versions = [
        %{
          name: "app_a",
          dependencies: [%{name: "phoenix", version: "~> 1.7"}],
          dev_dependencies: []
        },
        %{
          name: "app_b",
          dependencies: [%{name: "phoenix", version: "~> 1.6"}],
          dev_dependencies: []
        }
      ]

      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(repos_with_versions)
      versions = CrossRepoDeps.find_dependency_versions(graph)

      phoenix_versions = Enum.find(versions, &(&1.dependency == "phoenix"))
      assert phoenix_versions != nil
      assert phoenix_versions.versions != []
    end
  end

  describe "find_version_conflicts/1" do
    test "identifies conflicting versions" do
      repos_with_conflicts = [
        %{
          name: "app_a",
          dependencies: [%{name: "ecto", version: "~> 3.10"}],
          dev_dependencies: []
        },
        %{
          name: "app_b",
          dependencies: [%{name: "ecto", version: "~> 2.2"}],
          dev_dependencies: []
        }
      ]

      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(repos_with_conflicts)
      conflicts = CrossRepoDeps.find_version_conflicts(graph)

      # Should detect major version conflict
      assert conflicts != []
    end

    test "returns empty for compatible versions" do
      repos_compatible = [
        %{
          name: "app_a",
          dependencies: [%{name: "phoenix", version: "~> 1.7.0"}],
          dev_dependencies: []
        },
        %{
          name: "app_b",
          dependencies: [%{name: "phoenix", version: "~> 1.7.2"}],
          dev_dependencies: []
        }
      ]

      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(repos_compatible)
      conflicts = CrossRepoDeps.find_version_conflicts(graph)

      assert conflicts == []
    end
  end

  describe "suggest_upgrade_order/1" do
    test "returns repos in dependency order" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      order = CrossRepoDeps.suggest_upgrade_order(graph)

      # app_core should come before app_web and app_api
      core_idx = Enum.find_index(order, &(&1 == "app_core"))
      web_idx = Enum.find_index(order, &(&1 == "app_web"))
      api_idx = Enum.find_index(order, &(&1 == "app_api"))

      assert core_idx < web_idx
      assert core_idx < api_idx
    end
  end

  describe "find_cycles/1" do
    test "detects circular dependencies" do
      circular_repos = [
        %{name: "repo_a", dependencies: ["repo_b"], dev_dependencies: []},
        %{name: "repo_b", dependencies: ["repo_c"], dev_dependencies: []},
        %{name: "repo_c", dependencies: ["repo_a"], dev_dependencies: []}
      ]

      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(circular_repos)
      cycles = CrossRepoDeps.find_cycles(graph)

      assert cycles != []
    end

    test "returns empty for acyclic graphs" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)
      cycles = CrossRepoDeps.find_cycles(graph)

      assert cycles == []
    end
  end

  describe "dependency_depth/2" do
    test "calculates maximum dependency depth" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      # app_web -> app_core (depth 1)
      depth = CrossRepoDeps.dependency_depth(graph, "app_web")
      assert depth >= 1
    end

    test "returns 0 for repos with no dependencies" do
      repos = [
        %{name: "standalone", dependencies: [], dev_dependencies: []}
      ]

      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(repos)
      depth = CrossRepoDeps.dependency_depth(graph, "standalone")

      assert depth == 0
    end
  end

  describe "get_all_dependents/2" do
    test "returns transitive dependents" do
      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(@repos)

      dependents = CrossRepoDeps.get_all_dependents(graph, "app_core")

      dependent_names = Enum.map(dependents, & &1.name)
      assert "app_web" in dependent_names
      assert "app_api" in dependent_names
    end
  end
end
