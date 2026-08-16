# Justfile for corten

# Build the project
build:
    cargo build

# Build with FUSE support
build-fuse:
    cargo build --features fuse

# Run tests
test:
    cargo test

# Check code
check:
    cargo check
    cargo clippy -- -D warnings 2>/dev/null || true

# Run the CLI
run *ARGS:
    cargo run -- {{ARGS}}

# Build release
release:
    cargo build --release

# Format code
fmt:
    cargo fmt

# Clean build artifacts
clean:
    cargo clean

# Stage, generate a commit message from the diff via Ollama, commit,
# rebase onto origin/main, and push -- replaces the manual
# add/commit/pull --rebase/push sequence.
ship:
    #!/usr/bin/env bash
    set -euo pipefail
    git add -A
    diff="$(git diff --cached)"
    if [ -z "$diff" ]; then
        echo "Nothing staged to commit."
        exit 0
    fi
    # Keep the prompt bounded -- a huge diff risks exceeding the
    # model's context window; the first ~8000 chars is plenty for a
    # summary-quality commit message.
    truncated_diff="$(printf '%s' "$diff" | head -c 8000)"
    instruction="Write a single-line git commit message, imperative mood, under 72 characters, no quotes, no markdown, no trailing period, summarizing this diff:"
    prompt="$(printf '%s\n\n%s' "$instruction" "$truncated_diff")"
    response="$(curl -sf https://ollama.akinus21.com/api/generate -d "$(jq -n --arg model "minimax-m2.7:cloud" --arg prompt "$prompt" '{model: $model, prompt: $prompt, stream: false}')" | jq -r '.response // empty')"
    msg="$(printf '%s' "$response" | tr -d '"' | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -z "$msg" ]; then
        echo "Ollama returned an empty commit message -- not committing. Check that ollama.akinus21.com is reachable and the model is available."
        exit 1
    fi
    echo "Generated commit message: $msg"
    git commit -m "$msg"
    git pull --rebase origin main
    git push origin main