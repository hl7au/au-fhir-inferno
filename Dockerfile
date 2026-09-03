FROM ruby:3.3.6

ENV INSTALL_PATH=/opt/inferno/
ENV APP_ENV=production
RUN mkdir -p $INSTALL_PATH

WORKDIR $INSTALL_PATH

# Select the dependency set: the default Gemfile (released test kits — what master
# builds once for staging + prod) or Gemfile.dev (bleeding-edge, unreleased test-kit
# commits) for preview environments. Each Gemfile has its own committed lockfile
# (Gemfile.lock / Gemfile.dev.lock).
ARG BUNDLE_GEMFILE=Gemfile
ENV BUNDLE_GEMFILE=$INSTALL_PATH$BUNDLE_GEMFILE

# Gemfile* also matches Gemfile.common, Gemfile.dev and the *.lock files.
ADD Gemfile* $INSTALL_PATH
RUN gem install bundler
# Frozen mode: build strictly from the committed lockfile so the image is reproducible
# and the build fails fast if the lockfile is out of sync with the Gemfile.
RUN bundle config set --local frozen 'true' && bundle install

ADD . $INSTALL_PATH

# The generated Jekyll landing site, served by lib/inferno_platform_template/static_site.rb
# instead of by a separate nginx image. _site is gitignored and built by
# `rake web:generate_{dev,prod}` before docker build (see build-and-release-package.yaml),
# so it is not part of the source tree the ADD above copies from a clean checkout. Copied
# explicitly rather than relied on so a build with no generated site fails here, loudly,
# rather than producing an image that serves no landing page.
COPY ./_site $INSTALL_PATH/_site

EXPOSE 4567
CMD ["bundle", "exec", "puma"]
