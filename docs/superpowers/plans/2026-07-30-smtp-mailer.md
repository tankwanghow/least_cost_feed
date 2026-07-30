# SMTP Mailer Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Mailjet API-key mailer with a provider-agnostic SMTP mailer configured entirely through `MAIL_*` environment variables.

**Architecture:** Swoosh keeps its role as the mail abstraction; only the adapter changes from `Swoosh.Adapters.Mailjet` (HTTP API + Finch) to `Swoosh.Adapters.SMTP` (gen_smtp). The from-address moves out of the notifier source and into a `:mail_from` application env value set by `config/runtime.exs`. The deploy scripts thread five `MAIL_*` values into the generated docker-compose file, with the password prompted for rather than stored.

**Tech Stack:** Elixir 1.19, Phoenix 1.8, Swoosh 1.5, gen_smtp 1.2, bash deploy scripts, Docker Compose.

**Spec:** `docs/superpowers/specs/2026-07-30-smtp-mailer-design.md`

## Global Constraints

- Follow the pattern in `~/Projects/elixir/full_circle` except where this plan deliberately deviates (arg indices, dev `:mail_from` guard, prompted password).
- `gen_smtp` version floor: `~> 1.2`. Swoosh declares `{:gen_smtp, "~> 0.13 or ~> 1.0", optional: true}`, so `~> 1.2` satisfies it.
- `finch` is an *optional* dep of Swoosh (`{:finch, "~> 0.6", optional: true}`) — removing the explicit `mix.exs` entry drops it from the tree entirely. Nothing else in the app uses it.
- Production must raise at boot on any missing `MAIL_*` variable. Do not add fallbacks.
- The from-address default `{"LeastCostFeed", "tankwanghow@gmail.com"}` must be preserved so dev and test work with no env vars set.
- Do not modify `config/config.exs` (Local adapter) or `config/test.exs` (Test adapter).
- Do not modify the `Dockerfile` — `ca-certificates` is already installed in the runner image.

---

### Task 1: Make the from-address configurable

Moves the hardcoded from-address into application env so `runtime.exs` can set it per environment. This is the only task with behaviour worth unit-testing; do it first so the config task has something to configure.

**Files:**
- Modify: `lib/least_cost_feed/user_accounts/user_notifier.ex:7-18`
- Test: `test/least_cost_feed/user_accounts/user_notifier_test.exs` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the application env key `:mail_from` under the `:least_cost_feed` app, holding a `{name :: String.t(), address :: String.t()}` tuple. Task 2 sets this key in `config/runtime.exs`.

- [ ] **Step 1: Write the failing test**

Create `test/least_cost_feed/user_accounts/user_notifier_test.exs`:

```elixir
defmodule LeastCostFeed.UserAccounts.UserNotifierTest do
  # async: false — these tests mutate application env, which is global state.
  use ExUnit.Case, async: false

  alias LeastCostFeed.UserAccounts.UserNotifier

  setup do
    original = Application.fetch_env(:least_cost_feed, :mail_from)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:least_cost_feed, :mail_from, value)
        :error -> Application.delete_env(:least_cost_feed, :mail_from)
      end
    end)

    :ok
  end

  test "uses the configured :mail_from address" do
    Application.put_env(:least_cost_feed, :mail_from, {"LeastCostFeed", "noreply@example.com"})

    {:ok, email} =
      UserNotifier.deliver_confirmation_instructions(
        %{email: "user@example.com"},
        "http://localhost/confirm/abc"
      )

    assert email.from == {"LeastCostFeed", "noreply@example.com"}
  end

  test "falls back to the default address when :mail_from is unset" do
    Application.delete_env(:least_cost_feed, :mail_from)

    {:ok, email} =
      UserNotifier.deliver_confirmation_instructions(
        %{email: "user@example.com"},
        "http://localhost/confirm/abc"
      )

    assert email.from == {"LeastCostFeed", "tankwanghow@gmail.com"}
  end
end
```

Note: `deliver_confirmation_instructions/2` only reads `user.email`, so a bare map is a valid argument and no database fixture is needed.

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/least_cost_feed/user_accounts/user_notifier_test.exs`

Expected: the first test FAILS with an assertion showing `email.from` is
`{"LeastCostFeed", "tankwanghow@gmail.com"}` instead of the configured
`{"LeastCostFeed", "noreply@example.com"}`. The second test passes already —
that is expected, it pins the fallback behaviour we must not break.

- [ ] **Step 3: Read the configured address in the notifier**

In `lib/least_cost_feed/user_accounts/user_notifier.ex`, replace the private `deliver/3` function.

Current:

```elixir
  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"LeastCostFeed", "tankwanghow@gmail.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
```

New:

```elixir
  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    from_addr =
      Application.get_env(
        :least_cost_feed,
        :mail_from,
        {"LeastCostFeed", "tankwanghow@gmail.com"}
      )

    email =
      new()
      |> to(recipient)
      |> from(from_addr)
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/least_cost_feed/user_accounts/user_notifier_test.exs`
Expected: PASS, 2 tests, 0 failures.

- [ ] **Step 5: Run the full suite to confirm nothing regressed**

Run: `mix test`
Expected: all tests pass. The auth LiveView tests exercise these emails and must be unaffected.

- [ ] **Step 6: Commit**

```bash
git add lib/least_cost_feed/user_accounts/user_notifier.ex test/least_cost_feed/user_accounts/user_notifier_test.exs
git commit -m "refactor(mailer): read from-address from :mail_from app env"
```

---

### Task 2: Switch the adapter to SMTP

Swaps the dependency, the runtime configuration, and the supervision tree in one change — these cannot land independently, because removing Finch while `prod.exs` still names `Swoosh.ApiClient.Finch` would break production boot.

**Files:**
- Modify: `mix.exs:50-51`
- Modify: `config/runtime.exs:100-126`
- Modify: `config/prod.exs:11-12`
- Modify: `lib/least_cost_feed/application.ex:15-16`
- Modify: `CLAUDE.md:85`

**Interfaces:**
- Consumes: the `:mail_from` application env key from Task 1.
- Produces: production and dev-opt-in SMTP configuration driven by `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM`. Task 3 supplies these five variables to the container.

- [ ] **Step 1: Swap the dependency in `mix.exs`**

Replace these two lines:

```elixir
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
```

with:

```elixir
      {:swoosh, "~> 1.5"},
      {:gen_smtp, "~> 1.2"},
```

- [ ] **Step 2: Fetch dependencies**

```bash
mix deps.get
mix deps.unlock --unused
```

Expected: `gen_smtp` is fetched; `finch`, `mint`, and `nimble_pool` are removed from `mix.lock` as unused.

- [ ] **Step 3: Replace the mailer block in `config/runtime.exs`**

Delete lines 100–125 — everything from the `# ## Configuring the mailer` comment
through the `config :swoosh, api_client: ...` line. These are the last statements
inside the `if config_env() == :prod do` block; leave the block's closing `end` on
line 126 in place. Put this in their place, still inside the block:

```elixir
  # Mailer — SMTP in production, provider-agnostic. The MAIL_* env vars must
  # be present in the production environment. Boot crashes with a clear message
  # if any are missing so misconfiguration is loud rather than silent (would-be
  # password-reset emails getting dropped is worse than a failed deploy).
  mail_host =
    System.get_env("MAIL_HOST") ||
      raise "environment variable MAIL_HOST is missing."

  mail_port =
    System.get_env("MAIL_PORT") ||
      raise "environment variable MAIL_PORT is missing."

  mail_username =
    System.get_env("MAIL_USERNAME") ||
      raise "environment variable MAIL_USERNAME is missing."

  mail_password =
    System.get_env("MAIL_PASSWORD") ||
      raise "environment variable MAIL_PASSWORD is missing."

  mail_from =
    System.get_env("MAIL_FROM") ||
      raise "environment variable MAIL_FROM is missing."

  mail_port = String.to_integer(mail_port)

  config :least_cost_feed, LeastCostFeed.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: mail_host,
    port: mail_port,
    username: mail_username,
    password: mail_password,
    ssl: mail_port == 465,
    tls: :always,
    auth: :always,
    retries: 1,
    tls_options: [
      versions: [:"tlsv1.2", :"tlsv1.3"],
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(mail_host),
      depth: 99
    ]

  config :least_cost_feed, :mail_from, {"LeastCostFeed", mail_from}
```

- [ ] **Step 4: Append the dev opt-in block to `config/runtime.exs`**

At the very end of the file, *outside* the `:prod` block:

```elixir
# Development: opt in to real email sending by setting the MAIL_* env vars.
# Without them, dev keeps the Local adapter and emails appear at /dev/mailbox.
# For Gmail: MAIL_HOST=smtp.gmail.com, MAIL_PORT=587, MAIL_USERNAME and
# MAIL_FROM both set to the Gmail address, MAIL_PASSWORD set to a Gmail
# App Password (a normal account password will not work).
if config_env() == :dev and System.get_env("MAIL_HOST") do
  dev_mail_host = System.get_env("MAIL_HOST")
  dev_mail_port = String.to_integer(System.get_env("MAIL_PORT") || "587")

  config :least_cost_feed, LeastCostFeed.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: dev_mail_host,
    port: dev_mail_port,
    username: System.get_env("MAIL_USERNAME"),
    password: System.get_env("MAIL_PASSWORD"),
    ssl: dev_mail_port == 465,
    tls: :always,
    auth: :always,
    retries: 1,
    tls_options: [
      versions: [:"tlsv1.2", :"tlsv1.3"],
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(dev_mail_host),
      depth: 99
    ]

  # Only set :mail_from when MAIL_FROM is actually present — otherwise the
  # notifier's own default is better than {"LeastCostFeed", nil}.
  if dev_mail_from = System.get_env("MAIL_FROM") do
    config :least_cost_feed, :mail_from, {"LeastCostFeed", dev_mail_from}
  end
end
```

This guard is a deliberate deviation from full_circle, which sets `:mail_from` unconditionally.

- [ ] **Step 5: Disable the Swoosh API client in `config/prod.exs`**

Replace:

```elixir
# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: LeastCostFeed.Finch
```

with:

```elixir
# SMTP does not use Swoosh's HTTP API client.
config :swoosh, :api_client, false
```

Leave the `config :swoosh, local: false` line below it untouched.

- [ ] **Step 6: Drop Finch from the supervision tree**

In `lib/least_cost_feed/application.ex`, delete these two lines:

```elixir
      # Start the Finch HTTP client for sending emails
      {Finch, name: LeastCostFeed.Finch},
```

The `children` list becomes:

```elixir
    children = [
      LeastCostFeedWeb.Telemetry,
      LeastCostFeed.Repo,
      {DNSCluster, query: Application.get_env(:least_cost_feed, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LeastCostFeed.PubSub},
      # Start a worker by calling: LeastCostFeed.Worker.start_link(arg)
      # {LeastCostFeed.Worker, arg},
      # Start to serve requests, typically the last entry
      LeastCostFeedWeb.Endpoint
    ]
```

- [ ] **Step 7: Correct the stale line in `CLAUDE.md`**

Under Tech Stack, replace:

```markdown
- Swoosh + Mailjet for email delivery
```

with:

```markdown
- Swoosh + SMTP (gen_smtp) for email delivery, configured via `MAIL_*` env vars
```

- [ ] **Step 8: Verify compilation catches no dangling Finch references**

```bash
mix compile --force --warnings-as-errors
```

Expected: compiles clean, no warnings. Any `LeastCostFeed.Finch` reference left anywhere would surface here.

- [ ] **Step 9: Verify no Mailjet or Finch references remain in app code**

```bash
grep -rn "Mailjet\|MAILJET\|Finch" config/ lib/ mix.exs
```

Expected: no output at all.

- [ ] **Step 10: Verify the production config block is syntactically valid**

```bash
MIX_ENV=prod \
  DATABASE_URL=ecto://u:p@localhost/db \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  PHX_HOST=example.com \
  MAIL_HOST=smtp.example.com \
  MAIL_PORT=587 \
  MAIL_USERNAME=user@example.com \
  MAIL_PASSWORD=secret \
  MAIL_FROM=user@example.com \
  mix run --no-start -e 'IO.inspect(Application.get_env(:least_cost_feed, :mail_from))'
```

Expected: prints `{"LeastCostFeed", "user@example.com"}`.

- [ ] **Step 11: Verify production refuses to boot without the mail vars**

```bash
MIX_ENV=prod \
  DATABASE_URL=ecto://u:p@localhost/db \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  PHX_HOST=example.com \
  mix run --no-start -e 'IO.puts("should not reach here")'
```

Expected: fails with `** (RuntimeError) environment variable MAIL_HOST is missing.`

- [ ] **Step 12: Run the full suite**

```bash
mix test
mix credo
```

Expected: all tests pass; credo reports no new issues.

- [ ] **Step 13: Commit**

```bash
git add mix.exs mix.lock config/runtime.exs config/prod.exs lib/least_cost_feed/application.ex CLAUDE.md
git commit -m "feat(mailer): replace Mailjet adapter with SMTP

Swaps Swoosh.Adapters.Mailjet for Swoosh.Adapters.SMTP driven by MAIL_*
env vars, adds gen_smtp, and drops Finch (it existed only as Swoosh's
HTTP client for the Mailjet API)."
```

---

### Task 3: Thread MAIL_* through the deploy scripts

Removes the two live Mailjet secrets from the repository and supplies the five `MAIL_*` values to the container instead.

**Files:**
- Modify: `deploy_to_linode/generate_files_at_server.sh:1-33`
- Modify: `deploy_to_linode/launch.sh:79-104`

**Interfaces:**
- Consumes: the five `MAIL_*` variable names established in Task 2.
- Produces: nothing consumed by later tasks — this is the final task.

Before starting, note that `.gitignore` already carries `deploy.conf` and `!/docs/superpowers/`; no change is needed there.

- [ ] **Step 1: Record the current argument count as a baseline**

```bash
grep -o '\$GEN_FILE [^"]*' deploy_to_linode/launch.sh | sed 's/\$GEN_FILE //' | wc -w
```

Expected: `8`. This is the check that catches the off-by-one bug present in full_circle's copy; after Step 4 it must read `13`.

- [ ] **Step 2: Read the new positional args in `generate_files_at_server.sh`**

Replace:

```bash
DOCKER_CONTAINER_NAME=$8
APP_COMPOSE="/home/$IMAGE_NAME/docker-compose-${IMAGE_NAME}.yml"
```

with:

```bash
DOCKER_CONTAINER_NAME=$8
MAIL_HOST=$9
MAIL_PORT=${10}
MAIL_USERNAME=${11}
MAIL_PASSWORD=${12}
MAIL_FROM=${13}
APP_COMPOSE="/home/$IMAGE_NAME/docker-compose-${IMAGE_NAME}.yml"
```

Indices are `$9`–`${13}`, contiguous with `$8`. full_circle's copy starts at `${10}` and is wrong; do not copy it.

- [ ] **Step 3: Replace the Mailjet env lines in the generated compose file**

In the same file, replace the two `MAILJET_*` lines (the literal key and secret
values are deliberately not reproduced here — they are what this task removes):

```bash
      - MAILJET_API_KEY=<literal key in the script>
      - MAILJET_SECRET=<literal secret in the script>
```

with:

```bash
      - MAIL_HOST=${MAIL_HOST}
      - MAIL_PORT=${MAIL_PORT}
      - MAIL_USERNAME=${MAIL_USERNAME}
      - MAIL_PASSWORD=${MAIL_PASSWORD}
      - MAIL_FROM=${MAIL_FROM}
```

- [ ] **Step 4: Prompt for the SMTP password in `launch.sh`**

After the existing `DB_PWD` prompt block (which ends with the bare `echo` on line 83), insert:

```bash
stty -echo
echo -n "Please enter SMTP password for '$MAIL_USERNAME': "
read MAIL_PASSWORD
stty echo
echo
```

`MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, and `MAIL_FROM` are picked up from `deploy.conf` by the existing `while IFS='=' read` loop above — no parser change is needed.

- [ ] **Step 5: Pass the five values to the generator**

Replace this line:

```bash
sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/${IMAGE_NAME}/$GEN_FILE $DB_NAME $DB_USER $DB_PWD $PORT $DOMAIN_NAME $IMAGE_NAME $DOCKER_HUB_USERNAME $DOCKER_CONTAINER_NAME"
```

with:

```bash
sshpass -p $LINODE_PWD ssh root@$LINODE_IP "bash /home/${IMAGE_NAME}/$GEN_FILE $DB_NAME $DB_USER $DB_PWD $PORT $DOMAIN_NAME $IMAGE_NAME $DOCKER_HUB_USERNAME $DOCKER_CONTAINER_NAME $(printf '%q' "$MAIL_HOST") $(printf '%q' "$MAIL_PORT") $(printf '%q' "$MAIL_USERNAME") $(printf '%q' "$MAIL_PASSWORD") $(printf '%q' "$MAIL_FROM")"
```

`printf '%q'` quotes each value for the remote bash, so a password containing spaces or shell metacharacters survives local expansion and remote re-parsing.

- [ ] **Step 6: Verify both scripts parse**

```bash
bash -n deploy_to_linode/generate_files_at_server.sh
bash -n deploy_to_linode/launch.sh
```

Expected: no output from either (syntax OK).

- [ ] **Step 7: Verify the argument count now matches the indices read**

The Step 1 grep heuristic no longer works once `printf '%q' "$VAR"` is in the
line — its `[^"]*` stops at the first inner double quote and undercounts. Verify
functionally instead, by replaying the exact local-expansion-then-remote-reparse
semantics against a stub receiver:

```bash
SB=$(mktemp -d)
printf 'echo "argc=$#"\ni=1; for a in "$@"; do echo "  \\$$i = [$a]"; i=$((i+1)); done\n' > "$SB/gen.sh"
IMAGE_NAME=lcf; GEN_FILE=gen.sh
DB_NAME=db; DB_USER=u; DB_PWD=dbpw; PORT=4000; DOMAIN_NAME=ex.com
DOCKER_HUB_USERNAME=hub; DOCKER_CONTAINER_NAME=cont
MAIL_HOST=smtp.example.com; MAIL_PORT=587; MAIL_USERNAME=user@example.com
MAIL_PASSWORD='p@ss w0rd!'; MAIL_FROM=from@example.com
cmd="bash $SB/$GEN_FILE $DB_NAME $DB_USER $DB_PWD $PORT $DOMAIN_NAME $IMAGE_NAME $DOCKER_HUB_USERNAME $DOCKER_CONTAINER_NAME $(printf '%q' "$MAIL_HOST") $(printf '%q' "$MAIL_PORT") $(printf '%q' "$MAIL_USERNAME") $(printf '%q' "$MAIL_PASSWORD") $(printf '%q' "$MAIL_FROM")"
bash -c "$cmd"; rm -rf "$SB"
```

Expected: `argc=13`, with `$9`–`${13}` holding the five mail values in order and
`$12` reading exactly `[p@ss w0rd!]` — space and metacharacters intact.

- [ ] **Step 8: Verify the Mailjet secrets are gone from the deploy scripts**

```bash
grep -rn "MAILJET" deploy_to_linode/ config/ lib/ mix.exs
```

Expected: no output.

The literal key and secret values are not reproduced in this plan on purpose.
To confirm they are absent from the working tree generally, grep for the values
as they appear in `git show 471a2a6:deploy_to_linode/generate_files_at_server.sh`
rather than pasting them into a tracked file.

- [ ] **Step 9: Verify the generated compose block renders correctly**

Render the compose heredoc in isolation, redirecting it to a writable path and
truncating the script just before the nginx section. Note the anchored pattern
`/^echo "Creating Nginx/` — a bare `/nginx/` would match the `NGINX_CONF=`
assignment near the top of the script and delete the compose generation itself.

```bash
GENTEST=$(mktemp -d) && \
sed 's#^APP_COMPOSE=.*#APP_COMPOSE="'"$GENTEST"'/out.yml"#; /^echo "Creating Nginx/,$d' \
  deploy_to_linode/generate_files_at_server.sh > "$GENTEST/gen.sh" && \
bash "$GENTEST/gen.sh" db dbuser dbpass 4000 example.com least_cost_feed hub container \
  smtp.example.com 587 user@example.com 'p@ss w0rd!' from@example.com && \
cat "$GENTEST/out.yml"; rm -rf "$GENTEST"
```

Expected output — the five `MAIL_*` lines present with correct values (note the
password with its space and metacharacters survives intact) and no `MAILJET_*`:

```yaml
services:
  web:
    image: hub/least_cost_feed
    container_name: container
    environment:
      - DATABASE_URL=postgres://dbuser:dbpass@localhost:5432/db
      - DATABASE_QUERY_URL=postgres://dbuser_query:dbpass@localhost:5432/db
      - SECRET_KEY_BASE=6jObIP3Cd47fkXDM3TF8nWDPL27ZhfvCVW4MZEK766Uxz8YRTI3JlRShjHcNzZoH
      - PHX_HOST=example.com
      - MIX_ENV=prod
      - PORT=4000
      - MAIL_HOST=smtp.example.com
      - MAIL_PORT=587
      - MAIL_USERNAME=user@example.com
      - MAIL_PASSWORD=p@ss w0rd!
      - MAIL_FROM=from@example.com
    network_mode: host
```

- [ ] **Step 10: Commit**

```bash
git add deploy_to_linode/generate_files_at_server.sh deploy_to_linode/launch.sh
git commit -m "feat(deploy): supply SMTP MAIL_* vars instead of Mailjet keys

Removes the hardcoded Mailjet API key and secret from the repo. The SMTP
password is now prompted for, matching how LINODE_PWD and DB_PWD are
already handled; the other four values come from deploy.conf."
```

---

## After the plan: required manual steps

These are not code changes and are not part of any task, but the migration is not complete without them.

1. **Add the four keys to your local `deploy.conf`** (gitignored, not in the repo):

   ```
   MAIL_HOST=smtp.gmail.com
   MAIL_PORT=587
   MAIL_USERNAME=tankwanghow@gmail.com
   MAIL_FROM=tankwanghow@gmail.com
   ```

   For Gmail, `MAIL_PASSWORD` must be an **App Password** — a normal account password will not authenticate.

2. **Update the live server before deploying.** `deploy.sh` does *not* regenerate the compose file — `deploy_at_server.sh` only runs `docker compose down/up` against the file already on disk. The server's `/home/least_cost_feed/docker-compose-least_cost_feed.yml` still contains `MAILJET_*`, so deploying the new image against it will crash the app on boot at `raise "environment variable MAIL_HOST is missing."`

   Either re-run `./deploy_to_linode/launch.sh deploy.conf`, or hand-edit the compose file on the server to replace the two `MAILJET_*` entries with the five `MAIL_*` entries, **then** deploy.

3. **Rotate the exposed Mailjet credentials.** The API key and secret were committed to this repository in plaintext and remain in git history. Deleting them from the working tree does not un-expose them.

4. **Smoke-test real delivery in dev** before deploying:

   ```bash
   MAIL_HOST=smtp.gmail.com MAIL_PORT=587 \
   MAIL_USERNAME=tankwanghow@gmail.com MAIL_PASSWORD='<app password>' \
   MAIL_FROM=tankwanghow@gmail.com \
   mix phx.server
   ```

   Then trigger a password-reset email and confirm it arrives.
