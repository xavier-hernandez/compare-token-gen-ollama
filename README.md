# Comparing token generation across ollama models (with the help of Claude)


# bench.sh — Ollama Token Benchmark

A shell script for benchmarking token generation speed (tokens/sec) across Ollama models running in Docker on Unraid.

---

## Requirements

- Ollama running in a Docker container with port `11434` exposed
- `curl` and `awk` available inside the container (included by default in the Ollama image)

---

## Installation

Copy the script into your Ollama container or run it from your Unraid terminal:

```bash
# Copy script into container
docker cp bench.sh <container-name>:/bench.sh

# Make it executable
docker exec <container-name> chmod +x /bench.sh
```

---

## Usage

```bash
./bench.sh [OPTIONS]
```

### Options

| Flag | Description | Default |
|---|---|---|
| `-models` | Space or comma separated list of models to test | All installed models |
| `-runs` | Number of runs per model (averaged) | `3` |
| `-prompt` | Custom prompt to use for generation | Neural networks question |
| `-h` | Show help | — |

---

## Examples

**Benchmark all installed models:**
```bash
./bench.sh
```

**Benchmark specific models (space separated):**
```bash
./bench.sh -models "phi3:mini qwen3:14b"
```

**Benchmark specific models (comma separated):**
```bash
./bench.sh -models "phi3:mini, qwen3:14b-q8_0"
```

**With bracket/quote format:**
```bash
./bench.sh -models ["phi3:mini", "qwen3:14b"]
```

**Custom runs and prompt:**
```bash
./bench.sh -models "qwen3:14b mistral" -runs 5 -prompt "Write a Python quicksort."
```

**Run directly from outside the container:**
```bash
docker exec <container-name> sh /bench.sh -models "qwen3:14b mistral"
```

---

## Output

```
=== Ollama Token Benchmark ===
Models : all installed (3 found)
Runs   : 3
Prompt : Explain how neural networks learn in about 200 words....

--- Model: qwen3:14b ---
  Run 1: 663 tokens @ 41.3 tok/s
  Run 2: 651 tokens @ 41.3 tok/s
  Run 3: 574 tokens @ 41.3 tok/s
  >> Average: 41.3 tok/s

--- Model: mistral:latest ---
  Run 1: 222 tokens @ 85.3 tok/s
  Run 2: 235 tokens @ 84.6 tok/s
  Run 3: 263 tokens @ 84.2 tok/s
  >> Average: 84.7 tok/s

=== Summary (fastest first) ===
84.7 tok/s — mistral:latest
41.3 tok/s — qwen3:14b

=== Done ===
```

---

## How it works

The script calls Ollama's `/api/generate` endpoint with `stream: false` and reads `eval_count` (output tokens) and `eval_duration` (nanoseconds) directly from the response. This is Ollama's own internal timing measurement, making it more accurate than measuring wall-clock time around the HTTP call.

```
tokens/sec = eval_count / (eval_duration / 1,000,000,000)
```

Multiple runs are averaged to smooth out the first "cold" run where model weights are loaded into VRAM.

---

## Tips

**First run is always slower** — Ollama loads model weights into VRAM on the first call. Run 3+ iterations (default) so the average reflects steady-state performance.

**Check GPU utilisation** — if tok/s seems low for a model, check how much is GPU-resident:
```bash
docker exec <container-name> ollama ps
```
A `% GPU` below 100% means the model is spilling layers to system RAM, which kills throughput.

**RTX 5060 Ti (16GB) quick reference:**

| Quant | 14B VRAM usage | Expected tok/s |
|---|---|---|
| q4 (default) | ~9 GB | ~40 tok/s |
| q6_K | ~11 GB | ~30–35 tok/s |
| q8_0 | ~15–16 GB | ~8 tok/s (spilling) |

---

## Recommended Ollama Docker environment variables

```yaml
OLLAMA_KEEP_ALIVE: -1          # Keep models loaded in VRAM permanently
OLLAMA_LOAD_TIMEOUT: 5m
OLLAMA_NUM_PARALLEL: 1         # Single user — don't split VRAM
OLLAMA_CONTEXT_LENGTH: 16384   # Agents need long context
OLLAMA_KV_CACHE_TYPE: q8_0     # Halves KV cache VRAM vs f16
OLLAMA_NUM_GPU: 999            # Use all available GPUs
OLLAMA_FLASH_ATTENTION: 1      # More efficient attention, less VRAM
OLLAMA_GPU_OVERHEAD: 512000000 # Reserve 512MB buffer for stability
```

---

## Troubleshooting

**`Could not reach Ollama` error**
- Check the host URL in the config section matches your Unraid IP and exposed port
- Verify the container is running: `docker ps`

**Model error on a specific model**
- Confirm the model name with `ollama list` — names are case-sensitive and must include the tag (e.g. `qwen3:14b` not `qwen3`)

**Unexpectedly low tok/s**
- Run `ollama ps` to check GPU % — the model may be too large for your VRAM
- Try a lower quantization (e.g. switch from `q8_0` to `q4` or `q6_K`)
