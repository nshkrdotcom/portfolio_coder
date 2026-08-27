#!/usr/bin/env bash
# Run all numbered examples (01-19) sequentially.
#
# Examples 01-02 and 04-05 require no external services.
# Examples 03 and 06-15 require an LLM provider (API key or local provider).
# Examples 16-19 require agent-session or local providers.
#
# Usage:
#   ./examples/run_all.sh          # run all 19
#   ./examples/run_all.sh 1 5      # run 01 through 05 only
#   ./examples/run_all.sh 6 15     # run 06 through 15 only

set -euo pipefail

cd "$(dirname "$0")/.."

start=${1:-1}
end=${2:-19}

has_env() {
  local key=$1
  [[ -n "${!key:-}" ]]
}

llm_available=false
if has_env GEMINI_API_KEY || has_env OPENAI_API_KEY || has_env CODEX_API_KEY || has_env ANTHROPIC_API_KEY || \
   has_env OLLAMA_BASE_URL || has_env OLLAMA_HOST || has_env VLLM_BASE_URL || has_env VLLM_URL; then
  llm_available=true
fi

claude_available=false
if has_env ANTHROPIC_API_KEY || [[ "${ALLOW_CLAUDE_SESSION:-}" == "1" ]]; then
  claude_available=true
fi

codex_available=false
codex_dir="${CODEX_WORKING_DIR:-${CODEX_WORKDIR:-}}"
if [[ -n "$codex_dir" && -d "$codex_dir" ]]; then
  if has_env OPENAI_API_KEY || has_env CODEX_API_KEY || [[ "${ALLOW_CODEX_SESSION:-}" == "1" ]]; then
    codex_available=true
  fi
fi

ollama_available=false
if has_env OLLAMA_BASE_URL || has_env OLLAMA_HOST || [[ "${ALLOW_OLLAMA:-}" == "1" ]]; then
  ollama_available=true
fi

vllm_available=false
if has_env VLLM_ENABLED || has_env VLLM_BASE_URL || has_env VLLM_URL || [[ "${ALLOW_VLLM:-}" == "1" ]]; then
  vllm_available=true
fi

passed=0
failed=0
failures=()

for i in $(seq "$start" "$end"); do
  num=$(printf "%02d" "$i")
  file=$(ls examples/${num}_*.exs 2>/dev/null | head -1)

  if [ -z "$file" ]; then
    echo "--- SKIP: no file matching examples/${num}_*.exs ---"
    continue
  fi

  if [[ "$i" -eq 3 && "$llm_available" != "true" ]]; then
    echo "--- SKIP: $file (no LLM provider configured) ---"
    continue
  fi

  if [[ "$i" -ge 6 && "$i" -le 15 && "$llm_available" != "true" ]]; then
    echo "--- SKIP: $file (no LLM provider configured) ---"
    continue
  fi

  case "$i" in
    16)
      if [[ "$claude_available" != "true" ]]; then
        echo "--- SKIP: $file (Claude agent session not configured) ---"
        continue
      fi
      ;;
    17)
      if [[ "$codex_available" != "true" ]]; then
        echo "--- SKIP: $file (Codex agent session not configured) ---"
        continue
      fi
      ;;
    18)
      if [[ "$ollama_available" != "true" ]]; then
        echo "--- SKIP: $file (Ollama not configured) ---"
        continue
      fi
      ;;
    19)
      if [[ "$vllm_available" != "true" ]]; then
        echo "--- SKIP: $file (vLLM not configured) ---"
        continue
      fi
      ;;
  esac

  echo "=== Running $file ==="
  if mix run "$file"; then
    echo "--- PASS: $file ---"
    ((passed++)) || true
  else
    echo "--- FAIL: $file ---"
    ((failed++)) || true
    failures+=("$file")
  fi
  echo
done

echo "========================================"
echo "Results: $passed passed, $failed failed"
if [ ${#failures[@]} -gt 0 ]; then
  echo "Failures:"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
