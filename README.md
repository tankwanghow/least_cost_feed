# LeastCostFeed

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Production deploy (Linode)

This project lives in the `~/Projects/elixir/` monorepo and shares asset binaries with sibling
apps. See `~/Projects/elixir/shared_config/WORKSPACE_ASSETS.md`.

```bash
# Once per machine
~/Projects/elixir/.global_assets/setup.sh

# Deploy (from this directory)
./deploy_to_linode/deploy.sh deploy.conf
```

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
