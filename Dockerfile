ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.1
ARG DEBIAN_VERSION=bookworm-20260202-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app/least_cost_feed

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

COPY shared_config /app/shared_config
COPY .global_assets /app/.global_assets

COPY least_cost_feed/mix.exs least_cost_feed/mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY least_cost_feed/config/config.exs least_cost_feed/config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY least_cost_feed/priv priv
COPY least_cost_feed/lib lib
COPY least_cost_feed/assets assets

RUN mix assets.deploy

RUN mix compile

COPY least_cost_feed/config/runtime.exs config/

COPY least_cost_feed/rel rel
RUN mix release

FROM ${RUNNER_IMAGE}

# Runtime only: beam.smp links libstdc++ and libtinfo (already in the base
# image); glpsol comes from glpk-utils. No -dev/-doc packages or recommends.
RUN apt-get update -y && \
  apt-get install -y --no-install-recommends libstdc++6 openssl ca-certificates glpk-utils \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# C.UTF-8 ships with Debian's libc, so no locales package or locale-gen.
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/least_cost_feed/_build/${MIX_ENV}/rel/least_cost_feed ./

USER nobody

CMD ["/app/bin/server"]