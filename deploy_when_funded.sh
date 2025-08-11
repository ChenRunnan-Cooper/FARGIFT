#!/usr/bin/env bash
set -euo pipefail

# Load env
if [ -f .env ]; then
  # shellcheck disable=SC1091
  source .env
else
  echo ".env not found. Exiting." >&2
  exit 1
fi

# 支持多个RPC（空格或逗号分隔），否则回落到单一RPC
RAW_URLS="${ARBITRUM_SEPOLIA_RPC_URLS:-}" # 可选："https://a ... https://b ..." 或以逗号分隔
PRIMARY_URL="${ARBITRUM_SEPOLIA_RPC_URL:-}"
RPC_URLS=()
if [ -n "$RAW_URLS" ]; then
  # 将逗号替换为空格，再按空格拆分
  RAW_URLS=${RAW_URLS//,/ }
  for u in $RAW_URLS; do
    RPC_URLS+=("$u")
  done
fi
if [ -n "$PRIMARY_URL" ]; then
  RPC_URLS+=("$PRIMARY_URL")
fi

if [ ${#RPC_URLS[@]} -eq 0 ]; then
  echo "No RPC configured. Set ARBITRUM_SEPOLIA_RPC_URL or ARBITRUM_SEPOLIA_RPC_URLS." >&2
  exit 1
fi

PK="${PRIVATE_KEY:-}"
ETHERSCAN_KEY="${ARBISCAN_API_KEY:-}"
if [ -z "$PK" ]; then
  echo "PRIVATE_KEY missing. Exiting." >&2
  exit 1
fi

ADDR=$(cast wallet address --private-key "$PK")
# 阈值和轮询间隔（可通过环境变量覆盖）
THRESH_WEI=${THRESH_WEI:-2000000000000000}   # 默认 0.002 ETH
POLL_INTERVAL=${POLL_INTERVAL:-20}           # 默认 20s

choose_rpc_and_get_balance() {
  local addr="$1"
  local bal=""
  local used=""
  for url in "${RPC_URLS[@]}"; do
    # 抑制错误到stderr，失败返回空值
    bal=$(cast balance --rpc-url "$url" "$addr" 2>/dev/null || true)
    if [[ "$bal" =~ ^[0-9]+$ ]]; then
      used="$url"
      echo "$bal|$used"
      return 0
    fi
  done
  echo "|" # 无法获取
  return 1
}

echo "Monitoring balance on $ADDR (Arbitrum Sepolia)"
echo "Threshold: $THRESH_WEI wei (~$(python3 - <<<'print(%.18f)' 2>/dev/null || echo 0) ETH)"

while true; do
  result=$(choose_rpc_and_get_balance "$ADDR") || true
  BAL="${result%%|*}"
  USED_RPC="${result#*|}"

  if [ -n "$BAL" ]; then
    echo "Current balance(wei): $BAL (via: ${USED_RPC:-unknown})"
  else
    echo "Current balance(wei): 0 (RPC unavailable, retrying with backoff)"
  fi

  if [ -n "$BAL" ] && [ "$BAL" -ge "$THRESH_WEI" ]; then
    echo "Sufficient balance. Starting deployment... (rpc: ${USED_RPC:-$PRIMARY_URL})"
    forge script script/DeployPresent.s.sol:DeployPresent \
      --rpc-url "${USED_RPC:-$PRIMARY_URL}" \
      --private-key "$PK" \
      --broadcast \
      --verify \
      --etherscan-api-key "$ETHERSCAN_KEY" \
      -vvv | cat
    echo "Deployment attempt finished. Exiting watcher."
    exit 0
  fi

  # 抖动避免与公共RPC同步碰撞
  JITTER=$((RANDOM % 5))
  sleep $((POLL_INTERVAL + JITTER))
done 