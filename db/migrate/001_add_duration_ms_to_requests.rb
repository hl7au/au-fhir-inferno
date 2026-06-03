Sequel.migration do
  change do
    alter_table(:requests) do
      add_column :duration_ms, Integer
    end
  end
end
