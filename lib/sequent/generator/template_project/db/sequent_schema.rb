# frozen_string_literal: true

ActiveRecord::Schema.define do
  say_with_time 'Installing Sequent schema' do
    say 'Creating tables and indexes', true
    suppress_messages { execute File.read("#{File.dirname(__FILE__)}/sequent_schema.sql") }
    say 'Creating stored procedures and views', true
    suppress_messages { execute File.read("#{File.dirname(__FILE__)}/sequent_pgsql.sql") }
  end
end
