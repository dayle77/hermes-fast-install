# Hermes — быстрая установка

Скрипт для автоматической установки и настройки [Hermes Agent](https://github.com/NousResearch/hermes-agent) одной командой. Зашёл на сервер, вставил команду — готовый рабочий Hermes с Telegram-ботом.

## Что делает скрипт

1. Устанавливает зависимости (`curl`, Python, Node.js и др.)
2. Запускает официальный установщик Hermes
3. Записывает конфигурацию (`~/.hermes/config.yaml` и `~/.hermes/.env`)
4. Устанавливает и запускает gateway как systemd-сервис
5. Hermes сразу отвечает на сообщения в Telegram

## Требования

- Linux (Ubuntu/Debian, Fedora/RHEL, Arch) или macOS
- Права sudo (для установки зависимостей и systemd-сервиса)
- Telegram-бот, созданный через [@BotFather](https://t.me/BotFather)
- API-ключ одного из поддерживаемых провайдеров

## Установка

### 1. Скачать скрипт на сервер

```bash
curl -O https://raw.githubusercontent.com/.../install-hermes.sh
chmod +x install-hermes.sh
```

или скопировать через scp:

```bash
scp install-hermes.sh user@your-server:~/
```

### 2. Запустить

```bash
./install-hermes.sh \
  --telegram-token "ВАШ_ТОКЕН" \
  --telegram-id "ВАШ_CHAT_ID" \
  --provider openrouter \
  --provider-key "sk-or-..." \
  --model "anthropic/claude-opus-4-5"
```

## Параметры

| Параметр | Обязательный | Описание |
|---|---|---|
| `--telegram-token` | да | Токен бота от @BotFather |
| `--telegram-id` | да | Chat ID, куда бот будет отвечать |
| `--provider` | да | Провайдер LLM (см. список ниже) |
| `--provider-key` | да | API-ключ провайдера |
| `--model` | да | Название модели |
| `--base-url` | нет* | Base URL API (обязателен для `custom`) |
| `--skip-gateway` | нет | Не устанавливать systemd-сервис |
| `--reinstall` | нет | Переустановить, если Hermes уже стоит |

## Поддерживаемые провайдеры

| Провайдер | Значение `--provider` | Где взять ключ |
|---|---|---|
| OpenRouter | `openrouter` | [openrouter.ai/keys](https://openrouter.ai/keys) |
| OpenAI | `openai` | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| Anthropic | `anthropic` | [console.anthropic.com](https://console.anthropic.com) |
| Google Gemini | `google` | [aistudio.google.com](https://aistudio.google.com) |
| Mistral | `mistral` | [console.mistral.ai](https://console.mistral.ai) |
| Groq | `groq` | [console.groq.com/keys](https://console.groq.com/keys) |
| NovitaAI | `novitaai` | [novita.ai](https://novita.ai) |
| Кастомный | `custom` | — |

### Кастомный провайдер

Для любого OpenAI-совместимого API (локальный Ollama, LM Studio, собственный прокси и т.д.):

```bash
./install-hermes.sh \
  --telegram-token "ВАШ_ТОКЕН" \
  --telegram-id "ВАШ_CHAT_ID" \
  --provider custom \
  --provider-key "sk-..." \
  --base-url "https://my-llm.example.com/v1" \
  --model "my-model"
```

`--base-url` также работает с любым стандартным провайдером, если нужно переопределить endpoint (например, через прокси).

## Примеры

### OpenRouter + Claude

```bash
./install-hermes.sh \
  --telegram-token "1234567890:ABCdefGHIjklMNOpqrSTUvwxYZ" \
  --telegram-id "-1001234567890" \
  --provider openrouter \
  --provider-key "sk-or-v1-..." \
  --model "anthropic/claude-opus-4-5"
```

### OpenAI + GPT-4o

```bash
./install-hermes.sh \
  --telegram-token "1234567890:ABCdefGHIjklMNOpqrSTUvwxYZ" \
  --telegram-id "987654321" \
  --provider openai \
  --provider-key "sk-proj-..." \
  --model "gpt-4o"
```

### Локальный Ollama

```bash
./install-hermes.sh \
  --telegram-token "1234567890:ABCdefGHIjklMNOpqrSTUvwxYZ" \
  --telegram-id "987654321" \
  --provider custom \
  --provider-key "ollama" \
  --base-url "http://localhost:11434/v1" \
  --model "llama3.1:8b"
```

### Установка без systemd (только CLI)

```bash
./install-hermes.sh \
  --telegram-token "..." \
  --telegram-id "..." \
  --provider openrouter \
  --provider-key "sk-or-..." \
  --model "anthropic/claude-opus-4-5" \
  --skip-gateway
```

## Где взять Telegram Chat ID

1. Напишите любое сообщение своему боту
2. Откройте в браузере:
   ```
   https://api.telegram.org/bot<ВАШ_ТОКЕН>/getUpdates
   ```
3. Найдите поле `"chat": {"id": ...}` — это и есть ваш Chat ID

Для группового чата ID будет отрицательным, например `-1001234567890`.

## Что происходит после установки

Конфиг записывается в `~/.hermes/`:

```
~/.hermes/
├── config.yaml   # провайдер, модель, base_url
└── .env          # токены и API-ключи (права 600)
```

Gateway запускается как systemd-сервис `hermes-gateway` и стартует автоматически при перезагрузке сервера.

## Полезные команды

```bash
hermes                      # запустить интерактивный CLI
hermes gateway status       # статус gateway
hermes gateway logs         # логи в реальном времени
hermes gateway start        # запустить gateway вручную
hermes gateway stop         # остановить gateway
hermes model                # сменить модель
hermes config               # посмотреть все настройки
hermes doctor               # диагностика установки
```

Через systemd:

```bash
sudo systemctl status hermes-gateway
sudo systemctl restart hermes-gateway
sudo journalctl -u hermes-gateway -f
```

## Переустановка и обновление

```bash
# Переустановить с новыми параметрами
./install-hermes.sh --reinstall --telegram-token "..." ...

# Обновить только конфиг (без переустановки Hermes)
hermes config set model.default "новая-модель"
hermes config set model.provider openai
```

## Troubleshooting

**Бот не отвечает после установки**
```bash
hermes gateway logs   # смотрим ошибки
hermes doctor         # проверяем конфигурацию
```

**hermes: command not found**
```bash
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
# Добавить строку выше в ~/.bashrc или ~/.zshrc
```

**Ошибка API-ключа**
```bash
cat ~/.hermes/.env   # проверить что ключ записался правильно
```

**Переписать конфиг вручную**
```bash
hermes config edit   # откроет редактор
```
