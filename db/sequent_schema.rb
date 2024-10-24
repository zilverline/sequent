# frozen_string_literal: true

ActiveRecord::Schema.define do
  say_with_time 'Installing Sequent schema' do
    say 'Creating tables', true
    suppress_messages { execute File.read("#{File.dirname(__FILE__)}/sequent_schema_tables.sql") }
    say 'Creating table partitions', true
    suppress_messages { execute File.read("#{File.dirname(__FILE__)}/sequent_schema_partitions.sql") }
    say 'Creating constraints and indexes', true
    suppress_messages { execute File.read("#{File.dirname(__FILE__)}/sequent_schema_indexes.sql") }
    say 'Creating stored procedures and views', true
    suppress_messages { execute File.read("#{File.dirname(__FILE__)}/sequent_pgsql.sql") }
  end
end
