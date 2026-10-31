# ADR Tooling

## Настройка

Откройте:

```bash
nano config/tooling.mk
```

Основной путь к ADR repository:
```
ADR_REPO := /absolute/path/to/project
```

При необходимости измените пути ADR:
```
ADR_TEMPLATE := docs/adrs/ai/template.md
ADR_APPROVED := docs/adrs/ai/accepted
ADR_PROPOSED := docs/adrs/ai/proposed
ADR_DIAGRAMS := docs/diagrams
```

В этом же файле можно изменить модели:
```
MODEL_ARCHITECT := openai/gpt-6-astra
MODEL_WRITER := openai/gpt-6-sol
MODEL_REVIEWER := openai/gpt-6-astra
MODEL_FINDER := openai/gpt-6-luna-fast
MODEL_AUDITOR := openai/gpt-6-astra
```


Заполните поля в langfuse.secrets.json для подключения к Langfuse:
```
"public_key": ""
"secret_key": ""
```

После изменений:
```
make configure
make check
```


## Запуск

В терминале
```
make start
```

Или:
```
opencode
```

Основная команда внутри OpenCode:
```
/architect
```