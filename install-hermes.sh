#!/usr/bin/env bash
set -euo pipefail

# Подавить все интерактивные диалоги apt (needrestart, tzdata, etc.)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}${BOLD}[hermes]${RESET} $*"; }
ok()   { echo -e "${GREEN}${BOLD}[✓]${RESET} $*"; }
warn() { echo -e "${YELLOW}${BOLD}[!]${RESET} $*"; }
die()  { echo -e "${RED}${BOLD}[✗]${RESET} $*" >&2; exit 1; }

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
${BOLD}Hermes one-shot installer${RESET}

Usage:
  $0 --telegram-token <token> --telegram-id <chat_id> \\
     --provider <name> --provider-key <key> --model <model>

Required:
  --telegram-token   Telegram bot token (from @BotFather)
  --telegram-id      Telegram chat ID where the bot will respond
  --provider         LLM provider: openrouter | openai | anthropic |
                                   google | mistral | groq | novitaai |
                                   custom
  --provider-key     API key for the chosen provider
  --model            Model name, e.g. anthropic/claude-opus-4

Optional:
  --base-url         Custom base URL (required when --provider custom,
                     also works with any other provider to override endpoint)
  --skip-gateway     Don't install the gateway systemd service
  --reinstall        Re-run even if hermes is already installed
  -h, --help         Show this help

Examples:
  $0 --telegram-token "1234:ABC" --telegram-id "-100123456789" \\
     --provider openrouter --provider-key "sk-or-..." \\
     --model "anthropic/claude-opus-4-5"

  $0 --telegram-token "1234:ABC" --telegram-id "987654321" \\
     --provider openai --provider-key "sk-..." --model "gpt-4o"

  $0 --telegram-token "1234:ABC" --telegram-id "987654321" \\
     --provider custom --provider-key "sk-..." \\
     --base-url "https://my-llm.example.com/v1" --model "my-model"
EOF
  exit 0
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
TELEGRAM_TOKEN=""
TELEGRAM_ID=""
PROVIDER=""
PROVIDER_KEY=""
MODEL=""
BASE_URL=""
SKIP_GATEWAY=false
REINSTALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --telegram-token) TELEGRAM_TOKEN="$2"; shift 2 ;;
    --telegram-id)    TELEGRAM_ID="$2";    shift 2 ;;
    --provider)       PROVIDER="$2";       shift 2 ;;
    --provider-key)   PROVIDER_KEY="$2";   shift 2 ;;
    --model)          MODEL="$2";          shift 2 ;;
    --base-url)       BASE_URL="$2";       shift 2 ;;
    --skip-gateway)   SKIP_GATEWAY=true;   shift   ;;
    --reinstall)      REINSTALL=true;      shift   ;;
    -h|--help)        usage ;;
    *) die "Unknown argument: $1. Run $0 --help for usage." ;;
  esac
done

# ─── Validation ───────────────────────────────────────────────────────────────
[[ -z "$TELEGRAM_TOKEN" ]] && die "--telegram-token is required"
[[ -z "$TELEGRAM_ID"    ]] && die "--telegram-id is required"
[[ -z "$PROVIDER"       ]] && die "--provider is required"
[[ -z "$PROVIDER_KEY"   ]] && die "--provider-key is required"
[[ -z "$MODEL"          ]] && die "--model is required"
[[ "$PROVIDER" == "custom" && -z "$BASE_URL" ]] && die "--base-url is required when --provider custom"

# Map provider name → env variable name
case "$PROVIDER" in
  openrouter) PROVIDER_KEY_VAR="OPENROUTER_API_KEY" ;;
  openai)     PROVIDER_KEY_VAR="OPENAI_API_KEY"     ;;
  anthropic)  PROVIDER_KEY_VAR="ANTHROPIC_API_KEY"  ;;
  google)     PROVIDER_KEY_VAR="GOOGLE_API_KEY"      ;;
  mistral)    PROVIDER_KEY_VAR="MISTRAL_API_KEY"    ;;
  groq)       PROVIDER_KEY_VAR="GROQ_API_KEY"       ;;
  novitaai)   PROVIDER_KEY_VAR="NOVITAAI_API_KEY"   ;;
  custom)     PROVIDER_KEY_VAR="OPENAI_API_KEY"     ;;  # custom uses OpenAI-compatible API
  *)          PROVIDER_KEY_VAR="OPENAI_API_KEY"
              warn "Unknown provider '$PROVIDER', using OPENAI_API_KEY as key variable" ;;
esac

# ─── Print plan ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Hermes Fast Install${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Provider    : ${CYAN}${PROVIDER}${RESET}"
echo -e "  Model       : ${CYAN}${MODEL}${RESET}"
[[ -n "$BASE_URL" ]] && echo -e "  Base URL    : ${CYAN}${BASE_URL}${RESET}"
echo -e "  Telegram ID : ${CYAN}${TELEGRAM_ID}${RESET}"
echo -e "  Gateway     : ${CYAN}$( $SKIP_GATEWAY && echo 'skip' || echo 'install as service' )${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# ─── Step 1: Prerequisites ────────────────────────────────────────────────────
log "Checking prerequisites..."

install_pkg() {
  local pkg="$1"
  if command -v apt-get &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
      sudo -E apt-get install -y -o Dpkg::Options::="--force-confold" "$pkg"
  elif command -v dnf &>/dev/null;    then sudo dnf install -y "$pkg"
  elif command -v pacman &>/dev/null; then sudo pacman -Sy --noconfirm "$pkg"
  elif command -v brew &>/dev/null;   then brew install "$pkg"
  else die "$pkg not found and no supported package manager detected. Install $pkg manually."
  fi
}

if ! command -v curl &>/dev/null; then
  log "Installing curl..."
  install_pkg curl
fi

if ! command -v git &>/dev/null; then
  log "Installing git..."
  install_pkg git
fi

ok "Prerequisites ready"

# ─── Step 2: Install Hermes ───────────────────────────────────────────────────
HERMES_BIN=""
find_hermes() {
  for p in "$(command -v hermes 2>/dev/null)" \
            "$HOME/.local/bin/hermes" \
            "/usr/local/bin/hermes"; do
    [[ -x "$p" ]] && { HERMES_BIN="$p"; return 0; }
  done
  return 1
}

if find_hermes && [[ "$REINSTALL" == false ]]; then
  ok "Hermes already installed at $HERMES_BIN — skipping download (use --reinstall to force)"
else
  log "Downloading and running official Hermes installer..."
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | bash -s -- --non-interactive --skip-setup

  # Reload PATH so the new binary is visible in this session
  export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

  if ! find_hermes; then
    die "Hermes binary not found after installation. Check the installer output above."
  fi
  ok "Hermes installed at $HERMES_BIN"
fi

# ─── Step 3: Write configuration ──────────────────────────────────────────────
HERMES_DIR="${HERMES_HOME:-$HOME/.hermes}"
mkdir -p "$HERMES_DIR"

log "Writing $HERMES_DIR/.env ..."

# Preserve existing .env if present, update/add our keys
ENV_FILE="$HERMES_DIR/.env"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

set_env_var() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    # Replace existing line (sed -i works on both Linux and macOS)
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

set_env_var "TELEGRAM_BOT_TOKEN"           "$TELEGRAM_TOKEN"
set_env_var "TELEGRAM_HOME_CHANNEL"        "$TELEGRAM_ID"
set_env_var "TELEGRAM_FREE_RESPONSE_CHATS" "$TELEGRAM_ID"
set_env_var "TELEGRAM_ALLOWED_CHATS"       "$TELEGRAM_ID"
set_env_var "TELEGRAM_ALLOWED_USERS"       "$TELEGRAM_ID"
set_env_var "GATEWAY_ALLOW_ALL_USERS"      "false"
set_env_var "$PROVIDER_KEY_VAR"            "$PROVIDER_KEY"

ok ".env written"

log "Writing $HERMES_DIR/config.yaml ..."

CONFIG_FILE="$HERMES_DIR/config.yaml"

# Write config (overwrite model section, keep rest if file exists)
if [[ -f "$CONFIG_FILE" ]]; then
  "$HERMES_BIN" config set model.provider "$PROVIDER" 2>/dev/null || true
  "$HERMES_BIN" config set model.default  "$MODEL"    2>/dev/null || true
  "$HERMES_BIN" config set model.api_key  "$PROVIDER_KEY" 2>/dev/null || true
  if [[ -n "$BASE_URL" ]]; then
    "$HERMES_BIN" config set model.base_url "$BASE_URL" 2>/dev/null || true
  fi
else
  if [[ -n "$BASE_URL" ]]; then
    cat > "$CONFIG_FILE" <<YAML
model:
  provider: ${PROVIDER}
  default: ${MODEL}
  api_key: ${PROVIDER_KEY}
  base_url: ${BASE_URL}
YAML
  else
    cat > "$CONFIG_FILE" <<YAML
model:
  provider: ${PROVIDER}
  default: ${MODEL}
  api_key: ${PROVIDER_KEY}
YAML
  fi
fi

ok "config.yaml written"

# Если сервис уже запущен — рестартуем чтобы подхватить новый .env и config.yaml
if sudo systemctl is-active --quiet hermes-gateway 2>/dev/null; then
  log "Перезапускаем gateway для применения конфигурации..."
  sudo systemctl restart hermes-gateway
  ok "Gateway перезапущен"
fi

# ─── Step 4: Gateway (systemd service) ───────────────────────────────────────
if [[ "$SKIP_GATEWAY" == true ]]; then
  warn "Skipping gateway install (--skip-gateway)"
else
  log "Installing Hermes gateway service..."

  # Создаём systemd-юнит напрямую — обходим интерактивные промпты hermes gateway install
  SERVICE_FILE="/etc/systemd/system/hermes-gateway.service"
  GATEWAY_CMD="$HERMES_BIN gateway run"

  sudo tee "$SERVICE_FILE" > /dev/null <<SERVICE
[Unit]
Description=Hermes AI Gateway
After=network.target

[Service]
Type=simple
User=${USER}
Environment="PATH=${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=${ENV_FILE}
ExecStart=${GATEWAY_CMD}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

  sudo systemctl daemon-reload
  sudo systemctl enable hermes-gateway
  ok "Gateway service установлен: $SERVICE_FILE"

  log "Запускаем Hermes gateway..."
  if sudo systemctl start hermes-gateway; then
    ok "Gateway запущен"
  else
    warn "Не удалось запустить gateway."
    warn "Запустите вручную: sudo systemctl start hermes-gateway"
    warn "Логи: sudo journalctl -u hermes-gateway -f"
  fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  Hermes is ready!${RESET}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  Config dir  : ${CYAN}${HERMES_DIR}${RESET}"
echo -e "  Binary      : ${CYAN}${HERMES_BIN}${RESET}"
echo ""
echo -e "  ${BOLD}Useful commands:${RESET}"
echo -e "    hermes                          — start interactive CLI"
echo -e "    hermes gateway status           — check gateway status"
echo -e "    hermes gateway logs             — view gateway logs"
echo -e "    hermes model                    — switch model"
echo -e "    hermes config                   — view all settings"
echo ""
echo -e "  ${BOLD}Логи (при ошибках):${RESET}"
echo -e "    tail -f ~/.hermes/logs/gateway.log        — детальные логи gateway"
echo -e "    tail -f ~/.hermes/logs/errors.log         — только ошибки"
echo -e "    sudo journalctl -u hermes-gateway -f      — системные логи"
echo ""
if [[ "$SKIP_GATEWAY" == false ]]; then
  echo -e "  Send a message to your Telegram bot to verify it works."
  echo ""
fi
