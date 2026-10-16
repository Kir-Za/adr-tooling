# ADR Tooling

`adr-tooling` — среда для AI-assisted разработки Architecture Decision Records на базе OpenCode.

ADR и диаграммы хранятся в отдельном репозитории. Один clone `adr-tooling` работает с одним ADR-проектом.

## Структура

```text
software/
├── adr-tooling/
└── project-adr/
```

В ADR repository ожидается:

```text
docs/adrs/ai/
├── template.md
├── proposed/
└── approved/

docs/diagrams/
```

## Роли

```text
architect           → GPT-6 Astra
architecture-finder → GPT-6 Luna Fast
adr-writer          → GPT-6 Sol
adr-reviewer        → GPT-6 Astra
consistency-auditor → GPT-6 Astra
```

`architect`, `finder`, `reviewer`, `auditor` — read-only.

`adr-writer` может писать только в `proposed/`.

AI не может изменять `approved/`, canonical template или утверждать ADR. Модели для ролей задаются в `project.mk`

## Настройка

Создать локальную конфигурацию:

```bash
make init-project
```

Отредактировать:

```text
config/project.mk
```

Основные параметры:

```make
PROJECT_NAME := project
ADR_REPO := ../project-adr

ADR_TEMPLATE := docs/adrs/ai/template.md
ADR_APPROVED := docs/adrs/ai/approved
ADR_PROPOSED := docs/adrs/ai/proposed
ADR_DIAGRAMS := docs/diagrams
```

Затем:

```bash
make bootstrap
```

Успешный результат:

```text
Bootstrap: OK
```

## OpenCode v2.0.27

Из-за текущего поведения model routing Makefile явно передаёт `--agent` и `--model`.

После исправления OpenCode этот workaround можно будет убрать без изменения структуры проекта.