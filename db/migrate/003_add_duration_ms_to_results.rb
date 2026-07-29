Sequel.migration do
  change do
    alter_table(:results) do
      add_column :duration_ms, Integer
    end
  end
end
