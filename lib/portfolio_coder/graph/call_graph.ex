defmodule PortfolioCoder.Graph.CallGraph do
  @moduledoc """
  Call graph analysis for code intelligence.

  This module provides advanced call graph analysis on top of InMemoryGraph,
  including transitive call chains, cycle detection, entry point discovery,
  and call depth metrics.

  ## Features

  - Transitive callers/callees (recursive traversal)
  - Cycle detection in call chains
  - Entry point discovery (functions with no callers)
  - Leaf function discovery (functions with no callees)
  - Call depth analysis
  - Hot path detection (highly connected functions)

  ## Usage

      # Get all functions transitively called by a function
      {:ok, all_callees} = CallGraph.transitive_callees(graph, "MyModule.start/0")

      # Find cycles in the call graph
      {:ok, cycles} = CallGraph.find_cycles(graph)

      # Find entry points
      {:ok, entries} = CallGraph.entry_points(graph)
  """

  alias PortfolioCoder.Graph.InMemoryGraph

  @type graph :: InMemoryGraph.graph()

  @doc """
  Get all functions transitively called by a function (recursive callees).

  Options:
    - `:max_depth` - Maximum depth to traverse (default: 50)

  Returns a list of function IDs that are directly or indirectly called.
  """
  @spec transitive_callees(graph(), String.t(), keyword()) :: {:ok, [String.t()]}
  def transitive_callees(graph, function_id, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 50)
    result = traverse_callees(graph, function_id, MapSet.new(), 0, max_depth)
    # Remove the starting node from results
    {:ok, MapSet.delete(result, function_id) |> MapSet.to_list()}
  end

  @doc """
  Get all functions that transitively call a function (recursive callers).

  Options:
    - `:max_depth` - Maximum depth to traverse (default: 50)

  Returns a list of function IDs that directly or indirectly call this function.
  """
  @spec transitive_callers(graph(), String.t(), keyword()) :: {:ok, [String.t()]}
  def transitive_callers(graph, function_id, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 50)
    result = traverse_callers(graph, function_id, MapSet.new(), 0, max_depth)
    # Remove the starting node from results
    {:ok, MapSet.delete(result, function_id) |> MapSet.to_list()}
  end

  @doc """
  Find all cycles in the call graph.

  Returns a list of cycles, where each cycle is a list of function IDs
  representing a circular call chain.

  Options:
    - `:max_cycles` - Maximum number of cycles to return (default: 100)
  """
  @spec find_cycles(graph(), keyword()) :: {:ok, [[String.t()]]}
  def find_cycles(graph, opts \\ []) do
    max_cycles = Keyword.get(opts, :max_cycles, 100)

    {:ok, functions} = InMemoryGraph.nodes_by_type(graph, :function)
    function_ids = Enum.map(functions, & &1.id)

    cycles =
      function_ids
      |> Enum.reduce([], fn func_id, acc ->
        if length(acc) >= max_cycles do
          acc
        else
          case find_cycle_from(graph, func_id) do
            nil -> acc
            cycle -> [cycle | acc]
          end
        end
      end)
      |> Enum.uniq_by(&Enum.sort/1)
      |> Enum.take(max_cycles)

    {:ok, cycles}
  end

  @doc """
  Find entry points - functions that are not called by any other function.

  These are typically top-level API functions, callbacks, or test functions.
  """
  @spec entry_points(graph()) :: {:ok, [map()]}
  def entry_points(graph) do
    {:ok, functions} = InMemoryGraph.nodes_by_type(graph, :function)

    entries =
      functions
      |> Enum.filter(fn func ->
        {:ok, callers} = InMemoryGraph.callers(graph, func.id)
        callers == []
      end)

    {:ok, entries}
  end

  @doc """
  Find leaf functions - functions that don't call any other functions.

  These are typically utility functions, wrappers, or simple helpers.
  """
  @spec leaf_functions(graph()) :: {:ok, [map()]}
  def leaf_functions(graph) do
    {:ok, functions} = InMemoryGraph.nodes_by_type(graph, :function)

    leaves =
      functions
      |> Enum.filter(fn func ->
        {:ok, callees} = InMemoryGraph.callees(graph, func.id)
        callees == []
      end)

    {:ok, leaves}
  end

  @doc """
  Calculate the call depth of a function (max distance to any leaf function).

  A leaf function has depth 0. Functions that only call leaf functions have depth 1, etc.
  """
  @spec call_depth(graph(), String.t()) :: {:ok, non_neg_integer()} | {:error, :cycle_detected}
  def call_depth(graph, function_id) do
    case calculate_depth(graph, function_id, %{}) do
      {:ok, depth} -> {:ok, depth}
      :cycle -> {:error, :cycle_detected}
    end
  end

  @doc """
  Get call depth for all functions in the graph.

  Returns a map of function_id => depth.
  Functions involved in cycles are marked with :cycle.
  """
  @spec all_call_depths(graph()) :: {:ok, map()}
  def all_call_depths(graph) do
    {:ok, functions} = InMemoryGraph.nodes_by_type(graph, :function)

    depths =
      functions
      |> Enum.map(fn func ->
        depth =
          case call_depth(graph, func.id) do
            {:ok, d} -> d
            {:error, :cycle_detected} -> :cycle
          end

        {func.id, depth}
      end)
      |> Map.new()

    {:ok, depths}
  end

  @doc """
  Find hot paths - functions with the most incoming and outgoing calls.

  Returns functions sorted by connectivity (callers + callees count).

  Options:
    - `:limit` - Number of results (default: 10)
  """
  @spec hot_paths(graph(), keyword()) :: {:ok, [map()]}
  def hot_paths(graph, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    {:ok, functions} = InMemoryGraph.nodes_by_type(graph, :function)

    ranked =
      functions
      |> Enum.map(fn func ->
        {:ok, callers} = InMemoryGraph.callers(graph, func.id)
        {:ok, callees} = InMemoryGraph.callees(graph, func.id)
        connectivity = length(callers) + length(callees)
        Map.put(func, :connectivity, connectivity)
      end)
      |> Enum.sort_by(& &1.connectivity, :desc)
      |> Enum.take(limit)

    {:ok, ranked}
  end

  @doc """
  Get the call chain between two functions.

  Returns the shortest path of function calls from `from` to `to`,
  or an error if no path exists.

  Options:
    - `:max_depth` - Maximum chain length (default: 20)
  """
  @spec call_chain(graph(), String.t(), String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, :no_path}
  def call_chain(graph, from, to, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 20)
    InMemoryGraph.find_path(graph, from, to, max_depth: max_depth)
  end

  @doc """
  Analyze a module's internal call structure.

  Returns statistics about calls within a module.
  """
  @spec module_call_stats(graph(), String.t()) :: {:ok, map()}
  def module_call_stats(graph, module_id) do
    {:ok, functions} = InMemoryGraph.functions_of(graph, module_id)

    func_set = MapSet.new(functions)

    internal_calls =
      functions
      |> Enum.flat_map(fn func_id ->
        {:ok, callees} = InMemoryGraph.callees(graph, func_id)
        Enum.filter(callees, &MapSet.member?(func_set, &1))
      end)
      |> length()

    external_calls =
      functions
      |> Enum.flat_map(fn func_id ->
        {:ok, callees} = InMemoryGraph.callees(graph, func_id)
        Enum.reject(callees, &MapSet.member?(func_set, &1))
      end)
      |> Enum.uniq()
      |> length()

    stats = %{
      module: module_id,
      function_count: length(functions),
      internal_calls: internal_calls,
      external_dependencies: external_calls,
      cohesion: if(length(functions) > 1, do: internal_calls / length(functions), else: 0.0)
    }

    {:ok, stats}
  end

  @doc """
  Find strongly connected components in the call graph.

  A strongly connected component is a maximal set of functions where
  each function can reach every other function through calls.
  """
  @spec strongly_connected_components(graph()) :: {:ok, [[String.t()]]}
  def strongly_connected_components(graph) do
    {:ok, functions} = InMemoryGraph.nodes_by_type(graph, :function)
    function_ids = Enum.map(functions, & &1.id)

    # Find SCCs using Tarjan's algorithm approach
    # A node is in an SCC if there's a cycle including it
    sccs =
      function_ids
      |> Enum.reduce({MapSet.new(), []}, fn func_id, {processed, components} ->
        if MapSet.member?(processed, func_id) do
          {processed, components}
        else
          # Check if this function is part of a cycle
          case find_scc_from(graph, func_id, processed) do
            nil ->
              {MapSet.put(processed, func_id), components}

            scc when is_list(scc) and length(scc) > 1 ->
              new_processed = Enum.reduce(scc, processed, &MapSet.put(&2, &1))
              {new_processed, [scc | components]}

            _ ->
              {MapSet.put(processed, func_id), components}
          end
        end
      end)
      |> elem(1)
      |> Enum.uniq_by(&Enum.sort/1)

    {:ok, sccs}
  end

  # Private helpers

  defp traverse_callees(graph, function_id, visited, depth, max_depth) do
    if MapSet.member?(visited, function_id) do
      visited
    else
      visited = MapSet.put(visited, function_id)
      {:ok, direct_callees} = InMemoryGraph.callees(graph, function_id)

      if depth >= max_depth do
        # At max depth, add direct callees but don't recurse further
        Enum.reduce(direct_callees, visited, fn callee_id, acc ->
          MapSet.put(acc, callee_id)
        end)
      else
        Enum.reduce(direct_callees, visited, fn callee_id, acc ->
          traverse_callees(graph, callee_id, acc, depth + 1, max_depth)
        end)
      end
    end
  end

  defp traverse_callers(graph, function_id, visited, depth, max_depth) do
    if depth >= max_depth or MapSet.member?(visited, function_id) do
      visited
    else
      {:ok, direct_callers} = InMemoryGraph.callers(graph, function_id)
      visited = MapSet.put(visited, function_id)

      Enum.reduce(direct_callers, visited, fn caller_id, acc ->
        traverse_callers(graph, caller_id, acc, depth + 1, max_depth)
      end)
    end
  end

  defp find_cycle_from(graph, start_id) do
    find_cycle_dfs(graph, start_id, start_id, [start_id], MapSet.new([start_id]))
  end

  defp find_cycle_dfs(graph, start_id, current_id, path, visited) do
    {:ok, callees} = InMemoryGraph.callees(graph, current_id)

    Enum.find_value(callees, fn callee_id ->
      cond do
        callee_id == start_id and length(path) > 1 ->
          # Found cycle back to start
          path

        MapSet.member?(visited, callee_id) ->
          # Already visited this node in current path, not a cycle to start
          nil

        true ->
          # Continue DFS
          find_cycle_dfs(
            graph,
            start_id,
            callee_id,
            [callee_id | path],
            MapSet.put(visited, callee_id)
          )
      end
    end)
  end

  defp find_scc_from(graph, start_id, already_processed) do
    # Find all nodes reachable from start_id that can also reach start_id
    {:ok, reachable_forward} = transitive_callees(graph, start_id, max_depth: 50)
    forward_set = MapSet.new([start_id | reachable_forward])

    # Now check which of these can reach back to start_id
    scc_members =
      forward_set
      |> Enum.filter(fn node_id ->
        not MapSet.member?(already_processed, node_id) and
          (node_id == start_id or can_reach?(graph, node_id, start_id, 50))
      end)

    if length(scc_members) > 1 do
      scc_members
    else
      nil
    end
  end

  defp can_reach?(graph, from, to, max_depth) do
    {:ok, reachable} = transitive_callees(graph, from, max_depth: max_depth)
    to in reachable
  end

  @spec calculate_depth(graph(), String.t(), map()) :: {:ok, non_neg_integer()} | :cycle
  defp calculate_depth(graph, function_id, visited) do
    if Map.has_key?(visited, function_id) do
      :cycle
    else
      {:ok, callees} = InMemoryGraph.callees(graph, function_id)

      if callees == [] do
        {:ok, 0}
      else
        visited = Map.put(visited, function_id, true)

        callees
        |> Enum.reduce_while({:ok, 0}, fn callee_id, {:ok, max_depth} ->
          case calculate_depth(graph, callee_id, visited) do
            {:ok, depth} -> {:cont, {:ok, max(max_depth, depth + 1)}}
            :cycle -> {:halt, :cycle}
          end
        end)
      end
    end
  end
end
