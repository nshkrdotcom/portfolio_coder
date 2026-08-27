# Troubleshooting

## No LLM Providers Configured

Symptoms:
- `No LLM providers configured`
- examples skip with “no LLM provider configured”

Fix:
- Set `GEMINI_API_KEY`, `OPENAI_API_KEY`, or `ANTHROPIC_API_KEY`, or
- Set local provider env (`OLLAMA_BASE_URL`/`OLLAMA_HOST`, `VLLM_ENABLED`).

## OpenAI 429 / Insufficient Quota

`PortfolioCoder.LLM` classifies this as fatal and falls back to other providers.
If all providers fail, you’ll see context‑only output.

## Codex Agent Session Fails

- Ensure `CODEX_WORKING_DIR` exists
- Set `OPENAI_API_KEY` or `CODEX_API_KEY`

## Claude Agent Session Fails

- Set `ANTHROPIC_API_KEY`, or
- Run `claude login` and set `ALLOW_CLAUDE_SESSION=1`

## vLLM Issues

- Ensure `VLLM_ENABLED=1` and the runtime is configured
- Verify local GPU support and Python runtime
