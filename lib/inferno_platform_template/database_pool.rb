# Post-boot tuning for the Sequel connection pool.
#
# config/database.yml enables the connection_validator extension, but the interval it
# validates on is not a connect option: Sequel reads it from the pool object and defaults
# to 3600 seconds. An hour is far too coarse for the failure this guards against, so it is
# set here instead.
#
# Must run after Inferno::Application.finalize!, because the db provider builds the
# connection lazily and touching it earlier would start the container out of order.
module InfernoPlatformTemplate
  module DatabasePool
    # Seconds a connection may sit idle before it is pinged on checkout. Small enough that
    # a rescheduled database is noticed almost immediately, large enough that a busy pool
    # does not pay for a round trip on every request.
    VALIDATION_TIMEOUT = ENV.fetch('DB_CONNECTION_VALIDATION_TIMEOUT', 30).to_i

    def self.configure!
      pool = Inferno::Application['db.connection'].pool
      # sqlite development/test runs do not load the extension, so the accessor is absent.
      return unless pool.respond_to?(:connection_validation_timeout=)

      pool.connection_validation_timeout = VALIDATION_TIMEOUT
    rescue StandardError => e
      Inferno::Application['logger']&.warn(
        "DatabasePool.configure! skipped: #{e.class}: #{e.message}"
      )
    end
  end
end
