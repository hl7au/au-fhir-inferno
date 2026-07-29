# Undoes migrations 001 and 002. The request/validator timing middleware they backed has
# been removed: outbound FHIR and validator calls are Faraday calls, which the
# OpenTelemetry Faraday instrumentation already times, with the test attribution the
# validator_timing table never had.
#
# 001 and 002 are deliberately left in place rather than deleted. Sequel's IntegerMigrator
# refuses to run against a database whose recorded version is higher than the migrations
# present, so removing already-applied files would break the dev database this ran on.
Sequel.migration do
  up do
    drop_table?(:validator_timing)

    alter_table(:requests) do
      drop_column :duration_ms
    end
  end

  down do
    create_table?(:validator_timing) do
      String :id, primary_key: true, size: 36
      String :test_session_id, null: false, size: 255
      String :validator_url, size: 512
      Integer :duration_ms
      DateTime :created_at
      index :test_session_id
    end

    alter_table(:requests) do
      add_column :duration_ms, Integer
    end
  end
end
