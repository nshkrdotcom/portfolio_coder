# Examples

Run all examples with:

```bash
./examples/run_all.sh
```

## Categories

- **No external services**: 01, 02, 04, 05
- **LLM provider required**: 03, 06–15
- **Agent sessions**: 16 (Claude), 17 (Codex)
- **Local LLMs**: 18 (Ollama), 19 (vLLM)

## Environment Variables

Cloud LLMs:
- `GEMINI_API_KEY`
- `OPENAI_API_KEY`
- `CODEX_API_KEY`
- `ANTHROPIC_API_KEY`

Local LLMs:
- `OLLAMA_BASE_URL` / `OLLAMA_HOST`
- `VLLM_ENABLED=1` (or `VLLM_BASE_URL`/`VLLM_URL`)

Agent Sessions:
- `CODEX_WORKING_DIR`
- `CODEX_API_KEY` or `OPENAI_API_KEY`
- `ALLOW_CLAUDE_SESSION=1` (to run with `claude login` instead of API key)
