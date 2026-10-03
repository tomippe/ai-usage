# Contributing to AI Usage

AI Usage is open source under the [MIT License](LICENSE). You may fork, modify, and redistribute it freely.

## Prefer upstream pull requests

If your change fixes a bug, improves provider support, or helps other users, **please open a pull request on this repository first** (`tomippe/ai-usage`) rather than keeping improvements only in a private fork.

That keeps one maintained line of releases (including [apps.tomippe.jp](https://apps.tomippe.jp/ai-usage/)) and avoids duplicated effort. We review PRs in good faith; small, focused changes are easiest to merge.

This is a **community expectation**, not a legal requirement under MIT. You are not obligated to contribute back, but we appreciate it when you do.

## Forks and distribution

- Forks and unofficial builds are welcome.
- If you **publish a binary or store listing**, use a **distinct app name** (do not imply it is the official “AI Usage” from tomippe). See [TRADEMARK.md](TRADEMARK.md).
- Do not commit secrets (`.env`, API keys, credentials). `.env` is gitignored; use `.env.example` as a template.

## Development

- Mac build: `./build.sh -app` (see `.cursor/rules/build.mdc`).
- Provider behavior: [docs/providers.md](docs/providers.md), [docs/claude-usage-fetch.md](docs/claude-usage-fetch.md).

## Language

Issues and PRs may be written in Japanese or English.
