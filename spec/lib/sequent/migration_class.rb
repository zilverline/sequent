if ActiveRecord::VERSION::MAJOR <= 4
  MigrationClass = ActiveRecord::Migration
else
  MigrationClass = ActiveRecord::Migration['4.2']
end
