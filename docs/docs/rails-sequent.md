---
title: Rails & Sequent
---

This guide gives a step by step overview on how to add Sequent to an existing Rails application.

## Prerequisites

- PostgreSQL database. Sequent only supports Postgres databases. There is no particular reason for this other than that we haven't had the need or time
to support any other databases.

## Guide assumptions

You are already familiar with Ruby on Rails and the core [Concepts](concepts.html) of Sequent.

For a seamless integration with the latest Rails, best is to adhere to the Rails naming conventions. In Rails everything under the `app` directory is autoloaded.
To make use of this feature, best is to put your domain classes under an `app` subdirectory. For instance in `app/domain/bank_account/bank_account_aggregate.rb`.
In this case Rails expects your domain class to be called `BankAccount::BankAccountAggregate`.
See the [Rails autoloading and reloading guide](https://guides.rubyonrails.org/autoloading_and_reloading_constants.html) for more details.

1. Add to your `Gemfile`

   ```
   gem 'sequent', git: 'https://github.com/zilverline/sequent'
   ```

2. Run `bundle install`

3. Copy the `sequent_schema.rb` file from [https://raw.githubusercontent.com/zilverline/sequent/master/db/sequent_schema.rb](https://raw.githubusercontent.com/zilverline/sequent/master/db/sequent_schema.rb) and put it in your `./db` directory.

4. Create `./db/sequent_migrations.rb`. This will contain your `view_schema` migrations. 
    
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

    For a complete overview on how Migrations work in Sequent, check out the [Migrations Guide](/docs/concepts/migrations.html)
   
  
5. Add the following snippet to your `Rakefile`

    ```ruby
    # Sequent requires a `SEQUENT_ENV` environment to be set
    # next to a `RAILS_ENV` 
    ENV['SEQUENT_ENV'] = ENV['RAILS_ENV'] ||= 'development'
    
    require 'sequent/rake/migration_tasks'
    
    Sequent::Rake::MigrationTasks.new.register_tasks!
    
    # The dependency of sequent:init on :environment ensures the Rails app is loaded
    # when running the sequent migrations. This is needed otherwise
    # the sequent initializer - which is required to run these rake tasks -
    # doesn't run
    task 'sequent:init' => [:environment]
    task 'sequent:migrate:init' => [:sequent_db_connect]
    
    task 'sequent_db_connect' do
      Sequent::Support::Database.connect!(ENV['SEQUENT_ENV'])
    end
   
    # Create custom rake task setting the SEQUENT_MIGRATION_SCHEMAS for
    # running the Rails migrations 
    task :migrate_public_schema do
      ENV['SEQUENT_MIGRATION_SCHEMAS'] = 'public'
      Rake::Task['db:migrate'].invoke
    end

    # Prevent rails db:migrate from being executed directly.
    Rake::Task['db:migrate'].enhance([:'sequent:db:dont_use_db_migrate_directly'])
    ```


    **You can't use rails db:migrate directly** anymore since  
    that will add all the tables of the `view_schema` and `sequent_schema`
    to the `schema.rb` file after running a Rails migration. To fix this
    the `rails db:migrate` must be wrapped in your own task setting the
    environment variable `SEQUENT_MIGRATION_SCHEMAS`.
    For safety reasons you can enchance and prepend the `rails db:migrate`
    with Sequents `sequent:db:dont_use_db_migrate_directly` Rake task
    so running it without `SEQUENT_MIGRATION_SCHEMAS` set will fail.
    {: .notice--warning}

6. Ensure your `database.yml` contains the schema_search_path: 

    ```yaml
    default:
      schema_search_path: <%= ENV['SEQUENT_MIGRATION_SCHEMAS'] || 'public, sequent_schema, view_schema' %>
    ```

7. Enable eager loading on all environments

Sequent internally relies on registries of classes of certain types. For instance it keeps track of all
`AggregateRoot` classes by adding them to a registry when `Sequent::Core::AggregateRoot` is extended.
For this to work properly, all classes must be eager loaded otherwise code depending on this fact might
produce unpredictable results. Set the `config.eager_load` to `true` for all environments 
(in production the Rails default is already `true`).

8. Add `./config/initializers/sequent.rb` containing at least:

    ```ruby
    require_relative '../../db/sequent_migrations'
   
    Rails.application.reloader.to_prepare do
      Sequent.configure do |config|
        config.migrations_class_name = 'SequentMigrations'
    
        config.command_handlers = [
          # add you Sequent::CommandHandler's here
        ]
    
        config.event_handlers = [
          # add you Sequent::Projector's or Sequent::Workflow's here
        ]

        config.database_config_directory = 'config'
      
        # this is the location of your sql files for your view_schema
        config.migration_sql_files_directory = 'db/sequent'
      end
    end
    ```

    **You must** wrap the sequent initializer code in `Rails.application.reloader.to_prepare` because during
    initialization, the autoloading hasn't run yet.

9. Run the following commands to create the `sequent_schema` and `view_schema`  

    ```bash
    bundle exec rake sequent:db:create_event_store
    bundle exec rake sequent:db:create_view_schema
    
    # only run this when you add or change projectors in SequentMigrations
    bundle exec rake sequent:migrate:online
    bundle exec rake sequent:migrate:offline    
    ```

10. Run `rails s`


### Where to put your domain classes

Rails uses [Zeitwerk](https://github.com/fxn/zeitwerk) for autoloading and reloading. To ensure your domain classes will also benefit from
this feature, put them under a subdirectory of the `app` folder and adhere to the Rails naming conventions.

One caveat is that this leads to an explosion of small files containing singular `Event`s and `Command`s.
The preference of the Sequent team is to group all `Event`s and `Command`s in a single file (e.g. `events|commands.rb`).
Luckily in Zeitwerk this is still possible. An example folder structure:

```
app/
  controllers/
  models/
  domain/ # <- you can pick any name
    banking/ # <- optional subdirectory
      bank_account.rb
      events.rb
      command_handler.rb
```

In the above example the `bank_account.rb` contains the `AggregateRoot` and looks as follows:

```ruby
module Banking # <- corresponds to the subdirectory banking
   class BankAccount < Sequent::AggregateRoot
   end
end
```

The `events.rb` file:

```ruby
module Banking
   module Events # <- because our file is called `events.rb` it expects a module Events to exist.
      class BankAccountCreated < Sequent::Event; end
      class BankAccountClosed < Sequent::Event; end
   end
end
```

The "downside" here is that you need to introduce an extra layer of naming to be able to group your events into a single file. 

### Rails Engines

Sequent in [Rails Engines](https://guides.rubyonrails.org/engines.html) work basically the same as a normal Rails application.
Some things to remember when working with Rails Engines:

1. The Sequent config must be set in the main application `config/initializers`
2. The main application is the maintainer of the `sequent_schema` and `view_schema`. 
   So copy over the migration sql files to the main application directory like you would when an Engine provides active record migrations.

Please checkout the Rails & Sequent example app in our [sequent-examples](https://github.com/zilverline/sequent-examples) Github repository.

