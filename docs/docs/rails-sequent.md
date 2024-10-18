---
title: Rails & Sequent
toc: true
toc_sticky: true
classes: []
---

This guide gives a step by step overview on how to add Sequent to an existing Rails application.

We assume you're already familiar with Ruby on Rails and the core [Concepts](concepts.html) of Sequent.

## Prerequisites
PostgreSQL database. Sequent only supports Postgres databases. There is no particular reason for this other than that
we haven't had the need or time to support any other databases.

## Guide

For a seamless integration with the latest Rails, it's best is to adhere to the Rails naming conventions.
In Rails everything under the `app` directory is autoloaded. To make use of this feature, it's best is to put your
domain classes under an `app` subdirectory. For instance in `app/domain/bank_account/bank_account_aggregate.rb`. In this
case Rails expects your domain class to be called `BankAccount::BankAccountAggregate`. See the
[Rails autoloading and reloading guide](https://guides.rubyonrails.org/autoloading_and_reloading_constants.html)
for more details.

### Installation

Add to your `Gemfile`
```
gem 'sequent'
```
and run `bundle install`

### Configuration

#### Sequent configuration

Add Sequent configuration in `config/initializers/sequent.rb` with:
```ruby
require_relative '../../db/sequent_migrations'

Rails.application.reloader.to_prepare do
  Sequent.configure do |config|
    config.migrations_class_name = 'SequentMigrations'
    config.enable_autoregistration = true
    config.event_store_cache_event_types = !Rails.env.development?

    config.database_config_directory = 'config'

    # this is the location of your sql files for your view_schema
    config.migration_sql_files_directory = 'db/sequent'
  end
end
```

We wrap the sequent initializer code inside `Rails.application.reloader.to_prepare` because during
initialization the autoloading hasn't run yet.
{: .notice--warning}

#### Eager loading

Enable eager loading for every Rails environment in `config/environments/*.rb`
```ruby
config.eager_load = true
```
Sequent internally relies on registries of classes of certain types. For instance it keeps track of all `AggregateRoot`
classes by adding them to a registry when `Sequent::Core::AggregateRoot` is extended. For this to work properly,
all classes must be eager loaded, otherwise code depending on this fact might produce unpredictable results.

#### Sequent's Unit Of Work
If you load Aggregates inside Controllers or ActiveJob (for example) you have to clear Sequent's Unit Of Work (stored
in the `Thread.current`).
With Rails this can be automatically done using Rack middleware. Add this to `application.rb`:
```ruby
config.middleware.use Sequent::Util::Web::ClearCache
```
This step is only necessary if you load Aggregates outside the scope of the Unit Of Work, which is automatically started
and committed via the `execute_commands` call. See using the
[AggregateRepository outside the Unit Of Work](concepts/aggregate-repository.html#advanced-usage-outside-the-commandservice-transaction) for more details.

#### Rake tasks

Add the following snippet to your `Rakefile`:
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
 ENV['SEQUENT_MIGRATION_SCHEMAS'] = nil
end

# Prevent rails db:migrate from being executed directly.
Rake::Task['db:migrate'].enhance([:'sequent:db:dont_use_db_migrate_directly'])
```

**Rails `db:migrate`**
At the last line in the `Rakefile` we deny using the Rails's `db:migrate` task directly. You can't use this task
directly anymore since that will add all the tables of the `view_schema` and `sequent_schema` to the `schema.rb` file
after running a Rails migration. Instead, the `rails db:migrate` must be wrapped in your own task where you set the
environment variable `SEQUENT_MIGRATION_SCHEMAS`. For safety reasons we've "enhanced" the `rails db:migrate` task with
Sequent's `sequent:db:dont_use_db_migrate_directly` task, so running it without `SEQUENT_MIGRATION_SCHEMAS` set will fail.
{: .notice--warning}

### Database setup

#### Sequent database schema

Download the
[`sequent/db/sequent_schema.rb`](https://github.com/zilverline/sequent/blob/master/db/sequent_schema.rb)
file and put it in the `db` directory:
```shell
curl -o db/sequent_schema.rb https://raw.githubusercontent.com/zilverline/sequent/refs/heads/master/db/sequent_schema.rb
```

#### View schema migrations

Create `db/sequent_migrations.rb`. This will contain your `view_schema` migrations.

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

#### Database configuration

Ensure your `database.yml` contains the correct adapter and schema_search_path:
```yaml
default: &default
   adapter: postgresql
   host: localhost
   port: 5432
   username: <%= ENV["POSTGRES_USER"] %>
   password: <%= ENV["POSTGRES_PASSWORD"] %>
   pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
   timeout: 5000
   schema_search_path: <%= ENV.fetch("SEQUENT_MIGRATION_SCHEMAS") { "public, sequent_schema, view_schema" } %>
```

#### Create the database
Run the following commands to create the `sequent_schema` and `view_schema`:
```bash
bundle exec rake sequent:db:create_event_store
bundle exec rake sequent:db:create_view_schema

# only run this when you add or change projectors in SequentMigrations
bundle exec rake sequent:migrate:online
bundle exec rake sequent:migrate:offline
```

### Done
All done, you should be able to run the Rails application without problems

```shell
bundle exec rails server
```
```text
=> Booting Puma
=> Rails 7.2.1 application starting in development
=> Run `bin/rails server --help` for more startup options
Puma starting in single mode...
* Puma version: 6.4.3 (ruby 3.3.5-p100) ("The Eagle of Durango")
*  Min threads: 3
*  Max threads: 3
*  Environment: development
*          PID: 54525
* Listening on http://127.0.0.1:3000
* Listening on http://[::1]:3000
Use Ctrl-C to stop
```

## Autoloading and reloading your domain

Rails uses Zeitwerk for autoloading and reloading. To ensure your domain classes will also benefit from this feature,
put them under a subdirectory of the `app` folder and
[adhere to the Rails naming conventions](https://guides.rubyonrails.org/autoloading_and_reloading_constants.html).

One caveat is that this leads to an explosion of small files containing singular `Event` classes and `Command` classes.
The preference of the Sequent team is to group all `Event` classes and `Command` classes in a single file
(e.g. `events.rb` / `commands.rb`). Luckily in Zeitwerk this is still possible. An example folder structure:

```bash
app/
  controllers/
  models/
  domain/ # <- you can pick any name
    banking/ # <- optional subdirectory
      bank_account.rb
      events.rb
      command_handler.rb
```

In the example above the `bank_account.rb` contains the `AggregateRoot` and looks as follows:

```ruby
module Banking # <- corresponds to the subdirectory banking
   class BankAccount < Sequent::AggregateRoot
   end
end
```

The `events.rb` contains the `Event` classes and looks as follows:

```ruby
module Banking
   module Events # <- because our file is called `events.rb` it expects a module Events to exist.
      class BankAccountCreated < Sequent::Event; end
      class BankAccountClosed < Sequent::Event; end
   end
end
```

The "downside" here is that you need to introduce an extra layer of naming to be able to group your events into a single
file.

## Rails Engines

Sequent in [Rails Engines](https://guides.rubyonrails.org/engines.html) work basically the same as a
normal Rails application. Some things to remember when working with Rails Engines:

1. The Sequent config must be set in the main application `config/initializers`.
2. The main application is the maintainer of the `sequent_schema` and `view_schema`. Copy over the migration SQL files
   to the main application directory like you would when an Engine provides ActiveRecord migrations.

Please checkout the Rails & Sequent example app in our [sequent-examples](https://github.com/zilverline/sequent-examples) Github repository.
