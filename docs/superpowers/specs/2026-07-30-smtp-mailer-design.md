# SMTP Mailer Migration — Design

**Date:** 2026-07-30
**Status:** Approved

## Goal

Replace the Mailjet API-key mailer with a provider-agnostic SMTP mailer, following the
pattern already in use in `~/Projects/elixir/full_circle`. Credentials move from
hardcoded literals in a deploy script to `MAIL_*` environment variables.

## Motivation

Today `config/runtime.exs` configures `Swoosh.Adapters.Mailjet` with `MAILJET_API_KEY` /
`MAILJET_SECRET`, and those two secrets are baked as plaintext literals into
`deploy_to_linode/generate_files_at_server.sh`. SMTP removes the vendor lock-in, removes
the live secrets from the repository, and makes this app consistent with full_circle.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | App config + deploy scripts | Production keeps working after the switch; the hardcoded Mailjet secrets leave the repo. |
| `MAIL_PASSWORD` delivery | Interactive prompt in `launch.sh` | Matches how `LINODE_PWD` and `DB_PWD` are already handled; keeps the secret out of `deploy.conf`. |
| Dev mailer | Opt-in SMTP | `MAIL_HOST` present in dev → SMTP; otherwise `Swoosh.Adapters.Local` and `/dev/mailbox`. Allows local smoke-testing of real delivery. |
| Finch | Removed | It exists solely as Swoosh's HTTP client for the Mailjet API. SMTP does not need it, and nothing else in the app uses it. |
| Missing prod env vars | Raise at boot | A loud failed deploy beats silently dropping password-reset emails. Mirrors full_circle. |

## Changes

### Application configuration

**`mix.exs`**
- Add `{:gen_smtp, "~> 1.2"}` (required by `Swoosh.Adapters.SMTP`).
- Remove `{:finch, "~> 0.13"}`.

**`config/runtime.exs`**
- In the `config_env() == :prod` branch, replace the `Swoosh.Adapters.Mailjet` block with
  an SMTP block. Read `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`,
  `MAIL_FROM`; each raises `"environment variable <NAME> is missing."` when absent.
  `MAIL_PORT` is converted with `String.to_integer/1`.
- Configure `Swoosh.Adapters.SMTP` with `relay`, `port`, `username`, `password`,
  `ssl: mail_port == 465`, `tls: :always`, `auth: :always`, `retries: 1`, and
  `tls_options: [versions: [:"tlsv1.2", :"tlsv1.3"], verify: :verify_peer,
  cacerts: :public_key.cacerts_get(), server_name_indication: String.to_charlist(mail_host),
  depth: 99]`.
- Set `config :least_cost_feed, :mail_from, {"LeastCostFeed", mail_from}`.
- Delete the `config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: ...` line and
  the surrounding Mailgun/Hackney boilerplate comments that no longer apply.
- Append a dev block *outside* the `:prod` branch:
  `if config_env() == :dev and System.get_env("MAIL_HOST")` → same SMTP adapter config,
  with `MAIL_PORT` defaulting to `"587"`. Set `:mail_from` only when `MAIL_FROM` is
  actually present, so an unset `MAIL_FROM` leaves the notifier's default in place rather
  than producing a `{"LeastCostFeed", nil}` from-address.

**`config/prod.exs`**
- `config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: LeastCostFeed.Finch`
  becomes `config :swoosh, :api_client, false`.
- `config :swoosh, local: false` stays.

**`lib/least_cost_feed/application.ex`**
- Remove the `{Finch, name: LeastCostFeed.Finch}` child and its preceding comment.

**`lib/least_cost_feed/user_accounts/user_notifier.ex`**
- `deliver/3` reads the from-address from
  `Application.get_env(:least_cost_feed, :mail_from, {"LeastCostFeed", "tankwanghow@gmail.com"})`
  instead of the hardcoded tuple. The default preserves current dev/test behaviour with no
  env vars set.

**Unchanged:** `config/config.exs` (Local adapter default), `config/test.exs` (Test
adapter), `Dockerfile` — the runtime image already installs `ca-certificates`, which
`:public_key.cacerts_get()` requires for peer verification.

### Deploy scripts

**`deploy_to_linode/generate_files_at_server.sh`**
- Read five new positional args: `MAIL_HOST=$9`, `MAIL_PORT=${10}`, `MAIL_USERNAME=${11}`,
  `MAIL_PASSWORD=${12}`, `MAIL_FROM=${13}`.
- In the generated compose file's `environment:` list, replace the two `MAILJET_*` lines
  (and their live secret values) with the five `MAIL_*` lines.

Note: full_circle's copy of this script reads `MAIL_HOST` from `${10}` through `${14}`
while its `launch.sh` passes only 8 arguments — an off-by-one that leaves those values
empty. This implementation uses the correct indices `$9`–`${13}`.

**`deploy_to_linode/launch.sh`**
- After the existing `DB_PWD` prompt, add an echo-off prompt for `MAIL_PASSWORD`.
- `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_FROM` come from `deploy.conf` through
  the existing key=value parser.
- Pass all five values to `$GEN_FILE`, each quoted with `printf '%q'` so a password
  containing spaces or shell metacharacters survives expansion by the local shell and
  re-parsing by the remote shell.

**`.gitignore`**
- Add `deploy.conf` (full_circle already ignores it; this repo did not).
- Add `!/docs/superpowers/` so specs are tracked despite the blanket `/docs/*` ignore.

**`CLAUDE.md`**
- The Tech Stack line "Swoosh + Mailjet for email delivery" becomes "Swoosh + SMTP
  (gen_smtp) for email delivery". One line, corrected because the change makes it false.

## Deployment procedure

`deploy.sh` does **not** regenerate the compose file — only `launch.sh` does. The live
server's `docker-compose-least_cost_feed.yml` still carries `MAILJET_API_KEY` and
`MAILJET_SECRET`. Because the new `runtime.exs` raises on a missing `MAIL_HOST`, deploying
the new image against the old compose file will **crash the app on boot**.

Before deploying, do one of:

1. Re-run `./deploy_to_linode/launch.sh deploy.conf` (regenerates the compose file), or
2. Hand-edit `/home/least_cost_feed/docker-compose-least_cost_feed.yml` on the server,
   replacing the two `MAILJET_*` entries with the five `MAIL_*` entries.

Then deploy as usual.

## Required environment variables

| Variable | Example | Notes |
|---|---|---|
| `MAIL_HOST` | `smtp.gmail.com` | SMTP relay hostname. |
| `MAIL_PORT` | `587` | `465` selects implicit SSL; anything else uses STARTTLS. |
| `MAIL_USERNAME` | `tankwanghow@gmail.com` | SMTP auth user. |
| `MAIL_PASSWORD` | — | For Gmail this must be an App Password; a normal account password will not authenticate. |
| `MAIL_FROM` | `tankwanghow@gmail.com` | Envelope/display from-address, paired with the name `LeastCostFeed`. |

## Verification

- `mix deps.get` then `mix compile --warnings-as-errors` — confirms nothing else
  referenced `LeastCostFeed.Finch`.
- `mix test` — the notifier tests use the Test adapter and the preserved default
  from-address, so they should pass unchanged.
- `mix credo` — no new issues.
- Manual: run the dev server with `MAIL_HOST`/`MAIL_PORT`/`MAIL_USERNAME`/`MAIL_PASSWORD`/
  `MAIL_FROM` set, trigger a password-reset email, and confirm real delivery.
- Manual: `bash -n` on both modified deploy scripts.

## Out of scope

- Changing email content, templates, or the set of emails sent.
- Reworking the deploy scripts beyond threading the `MAIL_*` values through.
- Fixing the off-by-one bug in full_circle's own copy of `generate_files_at_server.sh`.
