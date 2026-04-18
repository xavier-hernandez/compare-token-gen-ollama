#!/bin/sh

# ── config ──────────────────────────────────────────
RUNS=3
PROMPT="Explain how neural networks learn in about 200 words."
HOST="http://localhost:11434"
# ────────────────────────────────────────────────────

usage() {
  echo ""
  echo "Usage: $0 [-models \"model1 model2 model3\"] [-runs N] [-prompt \"text\"]"
  echo ""
  echo "  -models   Space or comma separated list of models (quoted)"
  echo "            If omitted, all installed models are benchmarked"
  echo "  -runs     Number of runs per model (default: 3)"
  echo "  -prompt   Custom prompt (default: neural networks question)"
  echo ""
  echo "Examples:"
  echo "  $0"
  echo "  $0 -models \"phi3:mini qwen3:14b\""
  echo "  $0 -models \"phi3:mini, qwen3:14b, mistral\" -runs 5"
  echo "  $0 -models \"qwen3:14b\" -prompt \"Write a Python quicksort.\""
  echo ""
  exit 0
}

CUSTOM_MODELS=""

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    -models|--models)
      # strip brackets, quotes, commas → space-separated
      CUSTOM_MODELS=$(echo "$2" | tr -d '[]"' | tr ',' ' ' | tr -s ' ')
      shift 2
      ;;
    -runs|--runs)
      RUNS="$2"
      shift 2
      ;;
    -prompt|--prompt)
      PROMPT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

echo ""
echo "=== Ollama Token Benchmark ==="

# decide model list
if [ -n "$CUSTOM_MODELS" ]; then
  MODELS="$CUSTOM_MODELS"
  echo "Models : $MODELS"
else
  MODELS_JSON=$(curl -s "$HOST/api/tags")
  if [ -z "$MODELS_JSON" ] || ! echo "$MODELS_JSON" | grep -q "models"; then
    echo "ERROR: Could not reach Ollama at $HOST or no models found."
    exit 1
  fi
  MODELS=$(echo "$MODELS_JSON" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
  MODEL_COUNT=$(echo "$MODELS" | wc -l)
  echo "Models : all installed ($MODEL_COUNT found)"
fi

echo "Runs   : $RUNS"
echo "Prompt : $(echo "$PROMPT" | cut -c1-60)..."
echo ""

results=""

for MODEL in $MODELS; do
  echo "--- Model: $MODEL ---"
  total_tps=0
  success=0

  i=1
  while [ $i -le $RUNS ]; do
    RESPONSE=$(curl -s -X POST "$HOST/api/generate" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"$MODEL\",\"prompt\":\"$PROMPT\",\"stream\":false}")

    if echo "$RESPONSE" | grep -q "eval_count"; then
      EVAL_COUNT=$(echo "$RESPONSE" | grep -o '"eval_count":[0-9]*' | grep -o '[0-9]*')
      EVAL_DUR=$(echo "$RESPONSE" | grep -o '"eval_duration":[0-9]*' | grep -o '[0-9]*')

      if [ -n "$EVAL_COUNT" ] && [ -n "$EVAL_DUR" ] && [ "$EVAL_DUR" -gt 0 ]; then
        TPS=$(awk "BEGIN {printf \"%.1f\", $EVAL_COUNT / ($EVAL_DUR / 1000000000)}")
        echo "  Run $i: $EVAL_COUNT tokens @ ${TPS} tok/s"
        total_tps=$(awk "BEGIN {print $total_tps + $TPS}")
        success=$((success + 1))
      else
        echo "  Run $i: could not parse response"
      fi
    else
      ERR=$(echo "$RESPONSE" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
      echo "  Run $i: error — ${ERR:-no response}"
    fi
    i=$((i + 1))
  done

  if [ $success -gt 0 ]; then
    AVG=$(awk "BEGIN {printf \"%.1f\", $total_tps / $success}")
    echo "  >> Average: ${AVG} tok/s"
    results="$results\n$AVG tok/s — $MODEL"
  else
    results="$results\n   failed — $MODEL"
  fi
  echo ""
done

echo "=== Summary (fastest first) ==="
printf "$results\n" | grep -v "^$" | sort -rn
echo ""
echo "=== Done ==="
