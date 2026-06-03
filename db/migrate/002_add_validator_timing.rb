Sequel.migration do
  change do
    create_table(:validator_timing) do
      String :id, primary_key: true, size: 36
      String :test_session_id, null: false, size: 255
      String :validator_url, size: 512
      Integer :duration_ms
      DateTime :created_at
      index :test_session_id
    end
  end
end
