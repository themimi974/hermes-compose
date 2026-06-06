# Hermes Agent — Docker Compose Wrapper

A Docker Compose wrapper to run [Hermes Agent](https://hermes-agent.nousresearch.com) with persistent data and workspace isolation.

## Quick Start

```bash
# Clone the wrapper (or use init-hermes.sh which does this automatically)
git clone https://github.com/themimi974/hermes-compose.git
cd hermes-compose

# Build
docker compose build

# Run with a provider
PROVIDER=ollama MODEL=llama3.1 docker compose run --rm hermes
PROVIDER=openrouter MODEL=meta-llama/llama-3.1-70b-instruct OPENROUTER_API_KEY=sk-or-... docker compose run --rm hermes
PROVIDER=nvidia NVIDIA_API_KEY=nvapi-... docker compose run --rm hermes
```

## Supported Providers

| Provider | ENV Var | Key Var | Default Model | Notes |
|----------|---------|---------|---------------|-------|
| NVIDIA NIM | `nvidia` | `NVIDIA_API_KEY` | `meta/llama-3.1-70b-instruct` | Cloud, free tier |
| OpenAI | `openai` | `OPENAI_API_KEY` | `gpt-4o` | Paid |
| Anthropic | `anthropic` | `ANTHROPIC_API_KEY` | `claude-sonnet-4-20250514` | Paid |
| OpenRouter | `openrouter` | `OPENROUTER_API_KEY` | `meta-llama/llama-3.1-70b-instruct` | Multi-provider |
| Google Gemini | `gemini` | `GOOGLE_API_KEY` | `gemini-2.0-flash` | Free tier |
| Ollama | `ollama` | (none) | `llama3.1` | Local |
| LM Studio | `lmstudio` | (none) | `local-model` | Local |
| Local (llama.cpp) | `local` | (none) | `local` | Local |
| Custom endpoint | `custom` | `CUSTOM_API_KEY` | `gpt-4o` | Any OpenAI-compatible API |

## Usage

### Using `init-hermes.sh` (recommended)

```bash
# Drop script to PATH
cp init-hermes.sh /usr/local/bin/

# Run in any project directory — interactive provider picker
cd ~/my-project
init-hermes

# Or specify provider via env var
PROVIDER=ollama MODEL=llama3.1 init-hermes
PROVIDER=nvidia NVIDIA_API_KEY=*** init-hermes
```

### Manual Docker Compose

```bash
# 1. Create .env in .hermes/
mkdir -p .hermes
cp .env.example .hermes/.env
# Edit .hermes/.env with your API key

# 2. Build
docker compose build

# 3. Run
PROVIDER=ollama MODEL=llama3.1 docker compose run --rm hermes
```

## Directory Layout

```
project/
├── .hermes-compose/      # Wrapper repo (Dockerfile, compose, entrypoint)
├── .hermes/              # Persistent data (config.yaml, .env, sessions)
└── ...                   # Your codebase (mounted as /workspace)
```

## Configuration

The `entrypoint.sh` script auto-generates `config.yaml` and `.env` on first run based on the `PROVIDER` env var.

### Example: Ollama (local, no API key needed)

```bash
export PROVIDER=ollama
export MODEL=llama3.1
# Optional: export OLLAMA_HOST=http://your-machine:11434
docker compose run --rm hermes
```

### Example: OpenRouter

```bash
export PROVIDER=openrouter
export MODEL=meta-llama/llama-3.1-70b-instruct
export OPENROUTER_API_KEY=sk-or-v1-...
docker compose run --rm hermes
```

### Example: Custom endpoint

```bash
export PROVIDER=custom
export CUSTOM_BASE_URL=http://your-api:8000/v1
export CUSTOM_API_KEY=your-key
docker compose run --rm hermes
```

## Ports

| Port | Service | Required |
|------|---------|----------|
| 8642 | OpenAI-compatible API | Only if `API_SERVER_ENABLED=true` |
| 9119 | Web dashboard | Only if `HERMES_DASHBOARD=1` |

## Troubleshooting

- **`NVIDIA_API_KEY is not set`** — You're still using the old NVIDIA-only config. Clean `rm -rf .hermes/*` and re-run with the correct `PROVIDER`.
- **Ollama can't connect** — Try `OLLAMA_HOST=http://host-gateway:11434` or use `network_mode: host` in docker-compose.yml.
- **Config not picking up provider** — Delete `.hermes/config.yaml` and `.hermes/.hermes_initialized` — the entrypoint regenerates on next run.

## License

MIT
