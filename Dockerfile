# Two stages on the same slim Ruby base. The build stage carries the compiler toolchain,
# headers and git that `bundle install` needs; the runtime stage gets only the installed
# bundle and the app. The previous single-stage image was built on the full ruby image
# (buildpack-deps: compilers, linux-libc-dev, ImageMagick and dozens of other -dev
# packages), none of which the app uses at runtime, and they made up nearly all of its
# vulnerability findings.
#
# Ruby stays at exactly 3.3.6 because inferno_suite_generator's gemspec declares
# required_ruby_version "= 3.3.6", so bundler refuses any other Ruby. 3.3.6 has no Debian
# trixie image, hence bookworm. Keep RUBY_VERSION in step with .ruby-version and the ruby
# directive in Gemfile.common.
ARG RUBY_VERSION=3.3.6
FROM ruby:${RUBY_VERSION}-slim-bookworm AS base

# The ruby:3.3.6 slim images predate upstream dropping the -dev packages from slim, so
# they still ship libssl-dev, libyaml-dev, libffi-dev, libgmp-dev and zlib1g-dev, which
# pull in libc6-dev and linux-libc-dev (over 3700 of the base's findings on their own).
# The runtime libraries Ruby links against are marked manually installed in the base, so
# the purge keeps them. The images were also last rebuilt in January 2025, when 3.3.7
# superseded them, so the upgrade applies the Debian security fixes published since.
RUN apt-get update -qq && \
    apt-get purge -y --auto-remove libffi-dev libgmp-dev libssl-dev libyaml-dev zlib1g-dev && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

ENV INSTALL_PATH=/opt/inferno/
ENV APP_ENV=production
RUN mkdir -p $INSTALL_PATH

WORKDIR $INSTALL_PATH

# Select the dependency set: the default Gemfile (released test kits, what master
# builds once for staging + prod) or Gemfile.dev (bleeding-edge, unreleased test-kit
# commits) for preview environments. Each Gemfile has its own committed lockfile
# (Gemfile.lock / Gemfile.dev.lock).
ARG BUNDLE_GEMFILE=Gemfile
ENV BUNDLE_GEMFILE=$INSTALL_PATH$BUNDLE_GEMFILE


FROM base AS build

# build-essential compiles the gems that ship no precompiled x86_64-linux build
# (bigdecimal, json, nio4r, oj, puma, racc). The -dev packages are the ones the base
# stage purges, restored here only; libssl-dev also keeps puma's SSL support compiled in,
# as it was on the full image. git fetches the git-sourced gems in Gemfile.common
# (validation_test_kit, inferno_suite_generator).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git \
      libffi-dev libgmp-dev libssl-dev libyaml-dev zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Gemfile* also matches Gemfile.common, Gemfile.dev and the *.lock files.
COPY Gemfile* $INSTALL_PATH
# The base image's bundler is the one the lockfiles are BUNDLED WITH; if a lockfile names a
# different version, bundler installs that version into the bundle and switches to it.
# Frozen mode: build strictly from the committed lockfile so the image is reproducible
# and the build fails fast if the lockfile is out of sync with the Gemfile.
# The downloaded .gem files, the bare git caches and the checkouts' .git directories are
# only needed to install, not to load, so they are dropped before the runtime copy.
RUN bundle config set --local frozen 'true' && \
    bundle install && \
    rm -rf /usr/local/bundle/cache /usr/local/bundle/bundler/gems/*/.git


FROM base

# GEM_HOME and BUNDLE_APP_CONFIG are both /usr/local/bundle in the ruby image, so this
# carries the installed gems, the git-sourced gem checkouts and the frozen setting.
COPY --from=build /usr/local/bundle /usr/local/bundle

ADD . $INSTALL_PATH

# The generated Jekyll landing site, served by lib/inferno_platform_template/static_site.rb
# (the app serves it itself; there is no separate web server image). _site is gitignored and built by
# `rake web:generate_{dev,prod}` before docker build (see build-and-release-package.yaml),
# so it is not part of the source tree the ADD above copies from a clean checkout. Copied
# explicitly rather than relied on so a build with no generated site fails here, loudly,
# rather than producing an image that serves no landing page.
COPY ./_site $INSTALL_PATH/_site

EXPOSE 4567
CMD ["bundle", "exec", "puma"]
