---
title: Rails & Sequent
---

This guide gives a step by step overview on how to add Sequent to an existing Rails application.

## Prerequisites

- Rails < 6. At the time of writing Sequent only supports Rails < 6
- Postgresql database. Sequent only supports Postgres databases. There is no particular reason for this other then we haven't had the need or time
to support any other databases.

## Guide assumptions

You are already familiar with Ruby on Rails and the core [Concepts](concepts.html) of Sequent.



1. Add `gem 'sequent', git: 'https://github.com/zilverline/sequent'`  to your `Gemfile`

2. Run `bundle install`

3. Copy the `sequent_schema.rb` file from [https://raw.githubusercontent.com/zilverline/sequent/master/db/sequent_schema.rb](https://raw.githubusercontent.com/zilverline/sequent/master/db/sequent_schema.rb) and put it in your `./config` directory.

4. Create `./config/sequent_migrations.rb`. This will contain your `view_schema` migrations. 
    
    ```ruby
    VIEW_SCHEMA_VERSION = 1
    
    class SequentMigrations < Sequent::Migrations::Projectors
      def self.version
        VIEW_SCHEMA_VERSION
      end
    
      def self.versions
        {
          '1' => [
            # List of migrations for version 1
          ],
        }
      end
    end
    
    ```

    For a complete overview on how Migrations work in Sequent checkout the [Migrations Guide](/docs/concepts/migrations.html)
   
  
5. Add the following snippet to your `Rakefile`

    ```ruby
    # Sequent requires a `RACK_ENV` environment to be set
    # next to a `RAILS_ENV` 
    ENV['RACK_ENV'] = ENV['RAILS_ENV'] ||= 'development'
    
    require 'sequent/rake/migration_tasks'
    
    require_relative 'config/initializers/sequent'
    Sequent::Rake::MigrationTasks.new.register_tasks!
    
    task "sequent:migrate:init" => [:sequent_db_connect]
    
    task "sequent_db_connect" do
      Sequent::Support::Database.connect!(ENV['RACK_ENV'])
    end
    ```

6. Ensure your `database.yml` contains the schema_search_path: 

    ```yaml
    default:
      schema_search_path: "public, sequent_schema, view_schema"
    ```

    **It is important** that `public` comes first. The first schema
    is used by Rails ActiveRecord and will therefor contain all
    your non event sourced tables.
    {: .notice--warning}

7. Add `./config/initializers/sequent.rb` containing at least:

    ```ruby
    require_relative '../sequent_migrations'
    
    Sequent.configure do |config|
      config.migrations_class_name = 'SequentMigrations'
    
      config.command_handlers = [
        # add you Sequent::CommandHandler's here
      ]
    
      config.event_handlers = [
        # add you Sequent::Projector's or Sequent::Workflows's here
      ]

      config.database_config_directory = 'config'
      
      # this is the location of your sql files for your view_schema
      config.migration_sql_files_directory = 'db/sequent'
    end
    
    ```

8. Run the following commands to create the `sequent_schema` and `view_schema`  

    ```bash
    bundle exec rake sequent:db:create_event_store
    bundle exec rake sequent:db:create_view_schema
    
    # only run this when you add or change projectors in SequentMigrations
    bundle exec rake sequent:migrate:online
    bundle exec rake sequent:migrate:offline    
    ```

9. `rails s`

Please checkout the Rails & Sequent example app in our [sequent-examples](https://github.com/zilverline/sequent-examples) Github repository.
