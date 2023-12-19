# Elixir + Phoenix
ARG EX_VERSION=1.15

FROM elixir:$EX_VERSION

# Install debian packages
RUN apt-get update
RUN apt-get install --yes build-essential inotify-tools postgresql-client

# Install Phoenix packages
ARG PHX_VERSION=1.5.6
RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix archive.install hex phx_new $PHX_VERSION

# Install node
# RUN curl -sL https://deb.nodesource.com/setup_6.x -o nodesource_setup.sh
# RUN bash nodesource_setup.sh
# RUN apt-get install --yes nodejs npm

WORKDIR /app
EXPOSE 4000