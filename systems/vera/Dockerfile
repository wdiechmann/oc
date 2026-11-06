# Build from systems/vera; supports Linux amd64 and arm64.
ARG RUBY_VERSION=3.4.4
FROM ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    VERA_OCR_LANGUAGES=dan+eng \
    OMP_THREAD_LIMIT=1
RUN apt-get update -qq && apt-get install --no-install-recommends -y \
    ca-certificates curl poppler-utils tesseract-ocr tesseract-ocr-dan tesseract-ocr-eng \
    && rm -rf /var/lib/apt/lists/*
FROM base AS build
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 4.0.15 --no-document && bundle install \
    && rm -rf /usr/local/bundle/cache /usr/local/bundle/ruby/*/cache
COPY . .
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile
FROM base
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails
RUN groupadd --gid 1000 rails && useradd --uid 1000 --gid 1000 --create-home rails \
    && mkdir -p /rails/tmp /rails/log && chown -R rails:rails /rails/tmp /rails/log
USER 1000:1000
EXPOSE 3001
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3001"]
