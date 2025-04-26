
# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.0.2
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Set environment
ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips pkg-config libpq-dev

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install 

# Copy application code
COPY . .

# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libsqlite3-0 \
      libvips \
      libpq5 \
      postgresql-client \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives


# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Create the entrypoint script directly in the Dockerfile
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Wait for PostgreSQL to be ready\n\
until pg_isready -h $DATABASE_HOST -p ${DATABASE_PORT:-5432} -U $DATABASE_USERNAME; do\n\
  echo "Waiting for PostgreSQL to be ready..."\n\
  sleep 2\n\
done\n\
\n\
# Create the database if it does not exist\n\
bundle exec rails db:prepare\n\
\n\
# Then exec the container main process\n\
exec "$@"' > /rails/entrypoint.sh

# Make the entrypoint script executable
RUN chmod +x /rails/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/rails/entrypoint.sh"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]

