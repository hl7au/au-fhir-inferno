FROM ruby:3.3.6

ENV INSTALL_PATH=/opt/inferno/
ENV APP_ENV=production
RUN mkdir -p $INSTALL_PATH

WORKDIR $INSTALL_PATH

# Select the dependency set: the default Gemfile (prod / released test kits) or
# Gemfile.dev (bleeding-edge, unreleased test-kit commits) for the dev environment.
# Each Gemfile has its own committed lockfile (Gemfile.lock / Gemfile.dev.lock).
ARG BUNDLE_GEMFILE=Gemfile
ENV BUNDLE_GEMFILE=$INSTALL_PATH$BUNDLE_GEMFILE

# Gemfile* also matches Gemfile.common, Gemfile.dev and the *.lock files.
ADD Gemfile* $INSTALL_PATH
RUN gem install bundler
# Frozen mode: build strictly from the committed lockfile so the image is reproducible
# and the build fails fast if the lockfile is out of sync with the Gemfile.
RUN bundle config set --local frozen 'true' && bundle install

ADD . $INSTALL_PATH

EXPOSE 4567
CMD ["bundle", "exec", "puma"]
