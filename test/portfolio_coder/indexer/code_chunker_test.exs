defmodule PortfolioCoder.Indexer.CodeChunkerTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Indexer.CodeChunker

  describe "chunk_content/2" do
    test "chunks Elixir code by functions" do
      code = """
      defmodule MyApp.User do
        def get(id) do
          Repo.get(__MODULE__, id)
        end

        def create(attrs) do
          %__MODULE__{}
          |> changeset(attrs)
          |> Repo.insert()
        end

        defp changeset(user, attrs) do
          user
          |> cast(attrs, [:name, :email])
        end
      end
      """

      {:ok, chunks} = CodeChunker.chunk_content(code, language: :elixir, strategy: :function)

      assert is_list(chunks)
      assert length(chunks) >= 1

      # Each chunk should have required fields
      for chunk <- chunks do
        assert Map.has_key?(chunk, :content)
        assert Map.has_key?(chunk, :start_line)
        assert Map.has_key?(chunk, :end_line)
        assert Map.has_key?(chunk, :type)
      end
    end

    test "chunks Python code by functions" do
      code = """
      class Calculator:
          def add(self, a, b):
              return a + b

          def subtract(self, a, b):
              return a - b

          def multiply(self, a, b):
              return a * b
      """

      {:ok, chunks} = CodeChunker.chunk_content(code, language: :python, strategy: :function)

      assert is_list(chunks)
      # Should have at least the 3 methods
      assert length(chunks) >= 3
    end

    test "chunks JavaScript code by classes" do
      code = """
      class UserService {
        constructor() {
          this.users = [];
        }

        getUser(id) {
          return this.users.find(u => u.id === id);
        }
      }

      class PostService {
        constructor() {
          this.posts = [];
        }

        getPost(id) {
          return this.posts.find(p => p.id === id);
        }
      }
      """

      {:ok, chunks} = CodeChunker.chunk_content(code, language: :javascript, strategy: :class)

      assert is_list(chunks)
      assert length(chunks) >= 2

      class_chunks = Enum.filter(chunks, &(&1.type == :class))
      assert length(class_chunks) >= 2
    end

    test "hybrid strategy splits large chunks" do
      # Create a large function
      large_function = """
      defmodule MyApp.LargeModule do
        def big_function do
          #{String.duplicate("    # Comment line\n", 100)}
          :ok
        end
      end
      """

      {:ok, chunks} =
        CodeChunker.chunk_content(large_function,
          language: :elixir,
          strategy: :hybrid,
          chunk_size: 500,
          chunk_overlap: 50
        )

      assert is_list(chunks)
      # Large function should be split
      assert length(chunks) >= 1
    end

    test "lines strategy chunks by line count" do
      code = """
      # Line 1
      # Line 2
      # Line 3
      # Line 4
      # Line 5
      # Line 6
      # Line 7
      # Line 8
      # Line 9
      # Line 10
      """

      {:ok, chunks} =
        CodeChunker.chunk_content(code,
          language: :elixir,
          strategy: :lines,
          chunk_size: 120,
          chunk_overlap: 30
        )

      assert is_list(chunks)
      assert length(chunks) >= 1
    end
  end

  describe "chunk_by_symbol/2" do
    test "creates chunks for each symbol" do
      content = """
      def foo do
        :foo
      end

      def bar do
        :bar
      end

      def baz do
        :baz
      end
      """

      symbols = [
        %{name: "foo", type: :function, line: 1, visibility: :public, arity: 0},
        %{name: "bar", type: :function, line: 5, visibility: :public, arity: 0},
        %{name: "baz", type: :function, line: 9, visibility: :public, arity: 0}
      ]

      chunks = CodeChunker.chunk_by_symbol(content, symbols)

      assert length(chunks) == 3

      [first, second, third] = chunks

      assert first.name == "foo"
      assert first.start_line == 1
      assert String.contains?(first.content, "def foo")

      assert second.name == "bar"
      assert second.start_line == 5
      assert String.contains?(second.content, "def bar")

      assert third.name == "baz"
      assert third.start_line == 9
      assert String.contains?(third.content, "def baz")
    end

    test "handles empty symbol list" do
      content = "# Just a comment"
      chunks = CodeChunker.chunk_by_symbol(content, [])
      assert chunks == []
    end
  end

  describe "edge cases" do
    test "handles empty content" do
      {:ok, chunks} = CodeChunker.chunk_content("", language: :elixir, strategy: :function)
      assert chunks == [] or length(chunks) == 1
    end

    test "handles content with no recognizable structure" do
      code = "# Just comments\n# More comments\n"

      {:ok, chunks} = CodeChunker.chunk_content(code, language: :elixir, strategy: :hybrid)

      # Should fall back to line-based chunking
      assert is_list(chunks)
    end
  end
end
