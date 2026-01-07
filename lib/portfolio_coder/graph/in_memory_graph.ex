defmodule PortfolioCoder.Graph.InMemoryGraph do
  @moduledoc """
  Simple in-memory code graph without external dependencies.

  This module provides graph building and querying functionality for code that has been
  parsed. It's useful for demos, testing, and small codebases where a full graph database
  like Neo4j isn't needed.

  ## Features

  - Build graphs from parsed code symbols and references
  - Query for callers/callees
  - Find dependencies between modules
  - Traverse the graph to find paths

  ## Node Types

  - `:module` - A module or class definition
  - `:function` - A function or method
  - `:file` - A source file
  - `:external` - An external dependency

  ## Edge Types

  - `:defines` - File defines module, module defines function
  - `:calls` - Function calls function
  - `:imports` - Module imports/uses another module
  - `:alias` - Module aliases another module

  ## Usage

      # Create a graph
      {:ok, graph} = InMemoryGraph.new()

      # Add parsed code
      :ok = InMemoryGraph.add_from_parsed(graph, parsed_result, file_path)

      # Query the graph
      {:ok, callees} = InMemoryGraph.callees(graph, "MyModule.my_function")
      {:ok, imports} = InMemoryGraph.imports_of(graph, "MyModule")
  """

  use GenServer

  @type graph :: GenServer.server()

  @type graph_node :: %{
          id: String.t(),
          type: atom(),
          name: String.t(),
          metadata: map()
        }

  @type graph_edge :: %{
          source: String.t(),
          target: String.t(),
          type: atom(),
          metadata: map()
        }

  # Client API

  @doc """
  Create a new in-memory graph.
  """
  @spec new(keyword()) :: {:ok, graph()} | {:error, term()}
  def new(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Add a node to the graph.
  """
  @spec add_node(graph(), graph_node()) :: :ok
  def add_node(graph, node) do
    GenServer.call(graph, {:add_node, node})
  end

  @doc """
  Add an edge to the graph.
  """
  @spec add_edge(graph(), graph_edge()) :: :ok
  def add_edge(graph, edge) do
    GenServer.call(graph, {:add_edge, edge})
  end

  @doc """
  Add nodes and edges from a parsed code result.
  """
  @spec add_from_parsed(graph(), map(), String.t()) :: :ok
  def add_from_parsed(graph, parsed, file_path) do
    GenServer.call(graph, {:add_from_parsed, parsed, file_path})
  end

  @doc """
  Get all nodes in the graph.
  """
  @spec nodes(graph()) :: {:ok, [graph_node()]}
  def nodes(graph) do
    GenServer.call(graph, :nodes)
  end

  @doc """
  Get all edges in the graph.
  """
  @spec edges(graph()) :: {:ok, [graph_edge()]}
  def edges(graph) do
    GenServer.call(graph, :edges)
  end

  @doc """
  Get a node by ID.
  """
  @spec get_node(graph(), String.t()) :: {:ok, graph_node()} | {:error, :not_found}
  def get_node(graph, id) do
    GenServer.call(graph, {:get_node, id})
  end

  @doc """
  Get all nodes of a specific type.
  """
  @spec nodes_by_type(graph(), atom()) :: {:ok, [graph_node()]}
  def nodes_by_type(graph, type) do
    GenServer.call(graph, {:nodes_by_type, type})
  end

  @doc """
  Get outgoing edges from a node.
  """
  @spec outgoing(graph(), String.t()) :: {:ok, [graph_edge()]}
  def outgoing(graph, node_id) do
    GenServer.call(graph, {:outgoing, node_id})
  end

  @doc """
  Get incoming edges to a node.
  """
  @spec incoming(graph(), String.t()) :: {:ok, [graph_edge()]}
  def incoming(graph, node_id) do
    GenServer.call(graph, {:incoming, node_id})
  end

  @doc """
  Get all functions/methods called by a given function.
  """
  @spec callees(graph(), String.t()) :: {:ok, [String.t()]}
  def callees(graph, function_id) do
    GenServer.call(graph, {:callees, function_id})
  end

  @doc """
  Get all functions/methods that call a given function.
  """
  @spec callers(graph(), String.t()) :: {:ok, [String.t()]}
  def callers(graph, function_id) do
    GenServer.call(graph, {:callers, function_id})
  end

  @doc """
  Get all modules imported by a given module.
  """
  @spec imports_of(graph(), String.t()) :: {:ok, [String.t()]}
  def imports_of(graph, module_id) do
    GenServer.call(graph, {:imports_of, module_id})
  end

  @doc """
  Get all modules that import a given module.
  """
  @spec imported_by(graph(), String.t()) :: {:ok, [String.t()]}
  def imported_by(graph, module_id) do
    GenServer.call(graph, {:imported_by, module_id})
  end

  @doc """
  Get all functions defined by a module.
  """
  @spec functions_of(graph(), String.t()) :: {:ok, [String.t()]}
  def functions_of(graph, module_id) do
    GenServer.call(graph, {:functions_of, module_id})
  end

  @doc """
  Find a path between two nodes.
  """
  @spec find_path(graph(), String.t(), String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, :no_path}
  def find_path(graph, from, to, opts \\ []) do
    GenServer.call(graph, {:find_path, from, to, opts})
  end

  @doc """
  Get graph statistics.
  """
  @spec stats(graph()) :: map()
  def stats(graph) do
    GenServer.call(graph, :stats)
  end

  @doc """
  Clear all nodes and edges from the graph.
  """
  @spec clear(graph()) :: :ok
  def clear(graph) do
    GenServer.call(graph, :clear)
  end

  # Server implementation

  @impl GenServer
  def init(_opts) do
    state = %{
      nodes: %{},
      edges: [],
      outgoing_index: %{},
      incoming_index: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:add_node, node}, _from, state) do
    nodes = Map.put(state.nodes, node.id, node)
    {:reply, :ok, %{state | nodes: nodes}}
  end

  @impl GenServer
  def handle_call({:add_edge, edge}, _from, state) do
    edges = [edge | state.edges]

    outgoing_index =
      Map.update(state.outgoing_index, edge.source, [edge], fn existing ->
        [edge | existing]
      end)

    incoming_index =
      Map.update(state.incoming_index, edge.target, [edge], fn existing ->
        [edge | existing]
      end)

    {:reply, :ok,
     %{state | edges: edges, outgoing_index: outgoing_index, incoming_index: incoming_index}}
  end

  @impl GenServer
  def handle_call({:add_from_parsed, parsed, file_path}, _from, state) do
    state = do_add_from_parsed(state, parsed, file_path)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:nodes, _from, state) do
    {:reply, {:ok, Map.values(state.nodes)}, state}
  end

  @impl GenServer
  def handle_call(:edges, _from, state) do
    {:reply, {:ok, state.edges}, state}
  end

  @impl GenServer
  def handle_call({:get_node, id}, _from, state) do
    case Map.get(state.nodes, id) do
      nil -> {:reply, {:error, :not_found}, state}
      node -> {:reply, {:ok, node}, state}
    end
  end

  @impl GenServer
  def handle_call({:nodes_by_type, type}, _from, state) do
    nodes =
      state.nodes
      |> Map.values()
      |> Enum.filter(fn n -> n.type == type end)

    {:reply, {:ok, nodes}, state}
  end

  @impl GenServer
  def handle_call({:outgoing, node_id}, _from, state) do
    edges = Map.get(state.outgoing_index, node_id, [])
    {:reply, {:ok, edges}, state}
  end

  @impl GenServer
  def handle_call({:incoming, node_id}, _from, state) do
    edges = Map.get(state.incoming_index, node_id, [])
    {:reply, {:ok, edges}, state}
  end

  @impl GenServer
  def handle_call({:callees, function_id}, _from, state) do
    callees =
      state.outgoing_index
      |> Map.get(function_id, [])
      |> Enum.filter(fn e -> e.type == :calls end)
      |> Enum.map(fn e -> e.target end)

    {:reply, {:ok, callees}, state}
  end

  @impl GenServer
  def handle_call({:callers, function_id}, _from, state) do
    callers =
      state.incoming_index
      |> Map.get(function_id, [])
      |> Enum.filter(fn e -> e.type == :calls end)
      |> Enum.map(fn e -> e.source end)

    {:reply, {:ok, callers}, state}
  end

  @impl GenServer
  def handle_call({:imports_of, module_id}, _from, state) do
    imports =
      state.outgoing_index
      |> Map.get(module_id, [])
      |> Enum.filter(fn e -> e.type in [:imports, :uses, :alias] end)
      |> Enum.map(fn e -> e.target end)

    {:reply, {:ok, imports}, state}
  end

  @impl GenServer
  def handle_call({:imported_by, module_id}, _from, state) do
    importers =
      state.incoming_index
      |> Map.get(module_id, [])
      |> Enum.filter(fn e -> e.type in [:imports, :uses, :alias] end)
      |> Enum.map(fn e -> e.source end)

    {:reply, {:ok, importers}, state}
  end

  @impl GenServer
  def handle_call({:functions_of, module_id}, _from, state) do
    functions =
      state.outgoing_index
      |> Map.get(module_id, [])
      |> Enum.filter(fn e -> e.type == :defines end)
      |> Enum.map(fn e -> e.target end)
      |> Enum.filter(fn id ->
        case Map.get(state.nodes, id) do
          %{type: :function} -> true
          _ -> false
        end
      end)

    {:reply, {:ok, functions}, state}
  end

  @impl GenServer
  def handle_call({:find_path, from, to, opts}, _from, state) do
    max_depth = Keyword.get(opts, :max_depth, 10)
    result = bfs_path(state, from, to, max_depth)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    node_counts =
      state.nodes
      |> Map.values()
      |> Enum.group_by(fn n -> n.type end)
      |> Enum.map(fn {type, nodes} -> {type, length(nodes)} end)
      |> Map.new()

    edge_counts =
      state.edges
      |> Enum.group_by(fn e -> e.type end)
      |> Enum.map(fn {type, edges} -> {type, length(edges)} end)
      |> Map.new()

    stats = %{
      node_count: map_size(state.nodes),
      edge_count: length(state.edges),
      nodes_by_type: node_counts,
      edges_by_type: edge_counts
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call(:clear, _from, _state) do
    state = %{
      nodes: %{},
      edges: [],
      outgoing_index: %{},
      incoming_index: %{}
    }

    {:reply, :ok, state}
  end

  # Private helpers

  defp do_add_from_parsed(state, parsed, file_path) do
    file_node = build_file_node(parsed, file_path)

    state
    |> add_node_to_state(file_node)
    |> add_symbols(parsed, file_node.id)
    |> add_references(parsed)
  end

  defp build_file_node(parsed, file_path) do
    %{
      id: file_path,
      type: :file,
      name: Path.basename(file_path),
      metadata: %{path: file_path, language: parsed.language}
    }
  end

  defp add_symbols(state, parsed, file_id) do
    Enum.reduce(parsed.symbols, state, fn symbol, acc ->
      add_symbol(acc, parsed.symbols, symbol, file_id)
    end)
  end

  defp add_symbol(state, symbols, symbol, file_id) do
    case symbol.type do
      :module -> add_module_symbol(state, symbol, file_id)
      :function -> add_function_symbol(state, symbols, symbol, file_id)
      :class -> add_class_symbol(state, symbol, file_id)
      _ -> state
    end
  end

  defp add_module_symbol(state, symbol, file_id) do
    module_id = symbol.name

    module_node = %{
      id: module_id,
      type: :module,
      name: symbol.name,
      metadata: %{line: symbol.line, arity: symbol.arity, visibility: symbol.visibility}
    }

    state
    |> add_node_to_state(module_node)
    |> add_edge_to_state(%{
      source: file_id,
      target: module_id,
      type: :defines,
      metadata: %{}
    })
  end

  defp add_function_symbol(state, symbols, symbol, file_id) do
    func_id = build_function_id(symbols, symbol)

    func_node = %{
      id: func_id,
      type: :function,
      name: symbol.name,
      metadata: %{line: symbol.line, arity: symbol.arity, visibility: symbol.visibility}
    }

    parent_module = find_parent_module(symbols, symbol)
    source = parent_module || file_id

    state
    |> add_node_to_state(func_node)
    |> add_edge_to_state(%{
      source: source,
      target: func_id,
      type: :defines,
      metadata: %{}
    })
  end

  defp add_class_symbol(state, symbol, file_id) do
    class_id = symbol.name

    class_node = %{
      id: class_id,
      type: :class,
      name: symbol.name,
      metadata: %{line: symbol.line, visibility: symbol.visibility}
    }

    state
    |> add_node_to_state(class_node)
    |> add_edge_to_state(%{
      source: file_id,
      target: class_id,
      type: :defines,
      metadata: %{}
    })
  end

  defp add_references(state, parsed) do
    Enum.reduce(parsed.references, state, fn ref, acc ->
      add_reference(acc, parsed.symbols, ref)
    end)
  end

  defp add_reference(state, symbols, ref) do
    source_module = find_module_at_line(symbols, ref.line)

    case ref.type do
      :import -> add_module_reference(state, source_module, ref.module, :imports, ref.line)
      :use -> add_module_reference(state, source_module, ref.module, :uses, ref.line)
      :alias -> add_module_reference(state, source_module, ref.module, :alias, ref.line)
      _ -> state
    end
  end

  defp add_module_reference(state, nil, _target_id, _edge_type, _line), do: state

  defp add_module_reference(state, source_module, target_id, edge_type, line) do
    state
    |> ensure_external_node(target_id)
    |> add_edge_to_state(%{
      source: source_module,
      target: target_id,
      type: edge_type,
      metadata: %{line: line}
    })
  end

  defp ensure_external_node(state, target_id) do
    if Map.has_key?(state.nodes, target_id) do
      state
    else
      ext_node = %{id: target_id, type: :external, name: target_id, metadata: %{}}
      add_node_to_state(state, ext_node)
    end
  end

  defp add_node_to_state(state, node) do
    nodes = Map.put(state.nodes, node.id, node)
    %{state | nodes: nodes}
  end

  defp add_edge_to_state(state, edge) do
    edges = [edge | state.edges]

    outgoing_index =
      Map.update(state.outgoing_index, edge.source, [edge], fn existing ->
        [edge | existing]
      end)

    incoming_index =
      Map.update(state.incoming_index, edge.target, [edge], fn existing ->
        [edge | existing]
      end)

    %{state | edges: edges, outgoing_index: outgoing_index, incoming_index: incoming_index}
  end

  defp build_function_id(symbols, function_symbol) do
    parent = find_parent_module(symbols, function_symbol)

    if parent do
      "#{parent}.#{function_symbol.name}/#{function_symbol.arity || 0}"
    else
      "#{function_symbol.name}/#{function_symbol.arity || 0}"
    end
  end

  defp find_parent_module(symbols, symbol) do
    symbols
    |> Enum.filter(fn s -> s.type == :module and s.line < symbol.line end)
    |> Enum.max_by(fn s -> s.line end, fn -> nil end)
    |> case do
      nil -> nil
      parent -> parent.name
    end
  end

  defp find_module_at_line(symbols, line) do
    symbols
    |> Enum.filter(fn s -> s.type == :module and s.line <= line end)
    |> Enum.max_by(fn s -> s.line end, fn -> nil end)
    |> case do
      nil -> nil
      module -> module.name
    end
  end

  defp bfs_path(state, from, to, max_depth) do
    queue = [{from, [from]}]
    visited = MapSet.new([from])

    do_bfs(state, queue, visited, to, max_depth)
  end

  defp do_bfs(_state, [], _visited, _to, _max_depth), do: {:error, :no_path}

  defp do_bfs(state, [{current, path} | rest], visited, to, max_depth) do
    cond do
      current == to ->
        {:ok, Enum.reverse(path)}

      length(path) >= max_depth ->
        do_bfs(state, rest, visited, to, max_depth)

      true ->
        {new_queue, new_visited} = bfs_expand(state, current, path, rest, visited)
        do_bfs(state, new_queue, new_visited, to, max_depth)
    end
  end

  defp bfs_expand(state, current, path, rest, visited) do
    neighbors =
      Map.get(state.outgoing_index, current, [])
      |> Enum.map(fn e -> e.target end)
      |> Enum.reject(fn n -> MapSet.member?(visited, n) end)

    new_visited = Enum.reduce(neighbors, visited, &MapSet.put(&2, &1))
    new_items = Enum.map(neighbors, fn n -> {n, [n | path]} end)

    {rest ++ new_items, new_visited}
  end
end
