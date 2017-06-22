# Sequent

[![Build Status](https://travis-ci.org/zilverline/sequent.svg?branch=master)](https://travis-ci.org/zilverline/sequent) [![Code Climate](https://codeclimate.com/github/zilverline/sequent/badges/gpa.svg)](https://codeclimate.com/github/zilverline/sequent) [![Test Coverage](https://codeclimate.com/github/zilverline/sequent/badges/coverage.svg)](https://codeclimate.com/github/zilverline/sequent)

Sequent is a CQRS and event sourcing framework written in Ruby.

In short: This means instead of storing the current state of your domain model we only store _what happened_ (events).

If you are unfamiliar with these concepts you can catch up with:

* [Event sourcing](http://martinfowler.com/eaaDev/EventSourcing.html)
* [Lars and Bob's presentation at GOTO Amsterdam](http://gotocon.com/dl/goto-amsterdam-2013/slides/BobForma_and_LarsVonk_EventSourcingInProductionSystems.pdf)
* [Erik's blog series](http://blog.zilverline.com/2011/02/10/towards-an-immutable-domain-model-monads-part-5/)
* [Simple CQRS example by Greg Young](https://github.com/gregoryyoung/m-r)
* [Google](http://www.google.nl/search?ie=UTF-8&q=cqrs+event+sourcing)

# Tutorial

## Getting started

    gem install sequent
    
    require 'sequent'

## Introduction

In short the main building blocks of CQRS and Eventsourcing are Commands, Aggregates and Events. To explain
how you can use sequent we start with an example of a simple domain (creating accounts) and write some specs and code.

Sequent provides a given, when, then stanza when testing your domain code. These test are typically very fast
since they do not rely on a database.

## Project setup

Our folder structure for this example is as follows:

    Gemfile
    Rakefile
    spec/
    lib/

First setup the `Gemfile`

    source "https://rubygems.org"
    
    # let's use the latest and greatest
    gem 'sequent', git: 'git@github.com:zilverline/sequent.git'


In `spec/spec_helper.rb` add the necessary plumbing code to be able to test. The helpers
provided by sequent expect an `@event_store`, `@repository` to exist in the tests. 

```ruby
# spec/spec_helper.rb
require 'bundler/setup'
Bundler.setup

require 'sequent/test'

RSpec.configure do |config|
  config.include Sequent::Test::CommandHandlerHelpers

  config.before :each do
    @event_store = Sequent::Test::CommandHandlerHelpers::FakeEventStore.new
    @repository = Sequent::Core::AggregateRepository.new(@event_store)
    @repository.clear
  end
end
```

In `spec/account_spec.rb` the actual tests for our domain are added. The first test will be to
add an account. In eventsourced system we typically test this by checking which Events will occur
after a certain Command is executed. The `when_command `helper provided by sequent expect an `@command_handler`
variable to exist.

```ruby
# spec/account_spec.rb
require 'spec_helper'

describe 'Account' do
  let(:aggregate_id) { Sequent.new_uuid }

  before :each do
    @command_handler = AccountCommandHandler.new
  end

  it 'creates an account' do
    when_command CreateAccount.new(aggregate_id: aggregate_id, name: 'ben')
    then_events AccountCreated.new(aggregate_id: aggregate_id, sequence_number: 1), 
      AccountNameChanged.new(aggregate_id: aggregate_id, sequence_number: 2, name: 'ben')
  end
end
```

Run the spec: `rake spec` and it will fail since none of the domain classes exist.

In `lib/domain.rb` we are going to create the domain code. For now we keep it simple
and put the Commands, CommandHandlers, Events and Aggregates all in the same file.

```ruby
# the command
class CreateAccount < Sequent::Core::Command
  attrs name: String
  validate_presence_of :name
end

# events
class AccountCreated < Sequent::Core::CreateEvent
end

class AccountNameChanged < Sequent::Core::Event
  attrs name: String
end

# aggregate root
class Account < Sequent::Core::AggregateRoot
  def initialize(command)
    super(command.aggregate_id)
    # apply will set the mandatory event attributes aggregate_id and sequence_number
    apply AccountCreated
    apply AccountNameChanged, name: command.name
  end

  on AccountCreated do
  end

  on AccountNameChanged do |event|
    @name = event.command
  end
end

# command handler
class AccountCommandHandler < Sequent::Core::BaseCommandHandler
  on CreateAccount do |command|
    repository.add_aggregate Account.new(command)
  end
end
```

Now when we run the spec: `rake spec` and it will succeed.

## More examples

See the [sequent example app](https://github.com/zilverline/sequent-examples)

# The Database

The database is actually split in 2 parts. The Eventstore and the View schema. The eventstore is where all events are stored.

## Eventstore

Sequent uses a Postgres database with the eventstore schema. The current schema is maintained in `db/sequent_schema.rb`.

It is strongly recommended to copy this schema into your first migration and use migrations to keep it up to date. You can use ActiveRecord migrations
with Sequent and provides a task to run them (see section on Rake Tasks).

If you have trouble migrating from an older schema, please let us know. We'll be glad to help out.

## View Schema

Besides the event store database schema your app needs view projections. Projections are versioned and kept in a different database schema, but in
the same database.

Sequent adds support to maintain both schemas in the same database. Set the `schema_search_path` in your database config to your event store schema and
your view projection schema, respectively. E.g. 'event_store, view_1'.

The view schema is not maintained through migrations but instead is rebuild from recorded events. Therefore, there are no migrations on the view schema.
Its schema should be provided as a schema definition (e.g. in `db/view_schema.rb`).

To load the view schema in a different database schema use the `Sequent::Support::ViewSchema` extension of `ActiveRecord::Schema` to define it.

For example:

```ruby
Sequent::Support::ViewSchema.define(view_projection: Sequent::Support::ViewProjection.new(..)) do
  create_table 'accounts' do |t|
    t.string 'name', null: false
    t.string 'email', null: false
  end
end
```

The support module is not required with sequent automatically. Require `sequent/support` to enable it.

## Rake Tasks for migrations

Sequent provides some Rake tasks to ease setup. To make them available in your project, add
the following to your `Rakefile`.

```ruby
begin
  require 'sequent/rake/tasks'
  Sequent::Rake::Tasks.new({db_config_supplier: YAML.load_file('db/database.yml'), environment: ENV['RACK_ENV'] || 'development'}).register!
rescue LoadError
  puts 'Sequent tasks are not available'
end
```

You *must* pass some options (`opts`) to tell Sequent your configuration.

* `db_config_supplier` — function that takes an environment and returns the database configs for that environment (e.g. `YAML.load_file('db/database.yml')`)
* `environment` — deployment environment (like `RAILS_ENV`) to get the appropriate database config
* `event_store_schema` — name of the database schema that contains the event store (defaults to `public`)
* `view_projection` — a `Sequent::Support::ViewProjection` that specifies your view schema
* `migration_path` — path to your ActiveRecord migrations directory (defaults to `db/migrate`)

And you're all set to use the Rake tasks (see `rake -T` for a description).

## Upgrading to a new view schema version

1. Install new version of you app on the server
2. Create new view schema in the database
3. Set application in maintenance mode
4. Replay all events
5. Switch to new version
6. Maintenance mode off

To support deploying sequent provides the following methods in the `EventStore`

`Sequent::Core::Eventstore.replay_events_from_cursor(block_size: 2000, get_events:, on_progress: )`

Sequent uses the `postgresql_cursor` gem for iterating through large result sets. The `block_size`
param is passed to the `each_row` method and denotes the number of rows to fetch per db block fetch.
The `get_events` is an `ActiveRecord::Relation` containing the stream of events. Typically this is ordered
per aggregate per sequence number. The `on_progress` parameter is a block that is called after the number
of rows in `block_size` are processed and at the end of the method. By default the `on_progress` just
prints the progress to `STDOUT` 

So a very simple replay of all events:

```ruby
all_events = Sequent::Core::EventRecord.order('aggregate_id asc, sequence_number asc')
Sequent::Core::Eventstore.replay_events_from_cursor(
  block_size: 2000, 
  get_events: all_events, 
)
```
    
This strategy is fine when you don't have many events and it is okay to have downtime when doing a view schema upgrade.

## Upgrading to a new view schema version with virtually no downtime

Since the view schema's can always be regenerated from events 
we can deploy and run migrations for a new version of a Sequent powered app with virtually 
no downtime since we can do the generation of the new view schema in the background.

1. Install new version of your app on the server
2. Create new view schema in the database
3. Replay all events in the new view schema while the current version of you app is running
4. When all events are replayed set application set application in maintenance mode
5. Get new events since 3.
6. Switch to new version
7. Maintenance mode off

To support this way of deploying sequent we can use the `on_progress` parameter of
the `EventStore.replay_events_from_cursor` method.

As we read earlier the `on_progress` parameter is a block that is called after the number
of rows in `block_size` are processed and at the end of the method. It takes 3 parameters
of which the last is the ids of the `EventRecord` replayed. We need to keep track of this
during step 3 so in step 5 we can query all events expect for those events. We can not
simply keep track of the last id replayed since sequences in postgres can be out of order.

Replay of all events (step 3):

```ruby
Sequent::Core::EventRecord.connection.execute('create table replay_ids(event_id numeric)')
all_events = Sequent::Core::EventRecord.order('aggregate_id asc, sequence_number asc')
Sequent::Core::Eventstore.replay_events_from_cursor(
  block_size: 2000, 
  get_events: all_events, 
  on_progress: ->(progress, done, ids_replayed) {

  }
)
```


# Reference Guide

Sequent provides the following concepts from a CQRS and an event sourced application:

* Commands
* CommandService
* CommandHandlers
* AggregateRepository
* Events
* EventHandlers
* Projectors
* Workflows
* EventStore
* Aggregates
* ValueObjects
* Snapshotting

## Commands
Commands are the instructions typically initiated by the users, for instance by submitting forms.
Good practive is to give them descriptive names like `PayInvoice`.
Commands in sequent use ActiveModel for validations.

```ruby
class PayInvoice < Sequent::Core::UpdateCommand
  validates_presence_of :pay_date
  attrs pay_date: Date, amount: Integer
end
```

Sequent will automatically add validators in `Sequent::Core::BaseCommand`s for frequently used classes like:

* Date
* DateTime
* Integer
* Boolean

When posted form the web and created like `PayInvoiceCommand.from_params(params[:pay_invoice_command])` its values are typically still all String.
Sequent takes care of parsing the string values to the correct types automatically when a Command is valid (`valid?`).
Its values will be parsed to the correct types by the CommandService. If you instantiate a Command manually with the correct types nothing will change.


## CommandService

Sequent provides a `Sequent::Core::CommandService` to propagate the commands to the correct aggregates. This is done
via the registered CommandHandlers.

```ruby
command = PayInvoiceCommand.new(aggregate_id: "10", pay_date: Date.today, amount: 100)
Sequent.command_service.execute_commands command
```

## CommandHandlers

CommandHandlers are responsible to interpreting the command and sending the correct message to an Aggregate, or in some
cases create a new Aggregate and store it in the AggregateRepository.

```ruby
class InvoiceCommandHandler < Sequent::Core::BaseCommandHandler
  on PayInvoiceCommand do |command|
    do_with_aggregate(command, Invoice) { |invoice| invoice.pay(command.pay_date, command.amount) }
  end
end
```

## AggregateRepository

Repository for aggregates. Implements the Unit-Of-Work and Identity-Map patterns
to ensure each aggregate is only loaded once per transaction and that you always get the same aggregate instance back.

On commit all aggregates associated with the Unit-Of-Work are queried for uncommitted events. After persisting these events
the uncommitted events are cleared from the aggregate.

The repository is keeps track of the Unit-Of-Work per thread, so can be shared between threads.

```ruby
AggregateRepository.new(Sequent.config.event_store)
```

## Events

Events describe what happened in the application. Events, like commands, have descriptive names in past tense e.g. InvoicePaidEvent

```ruby
class InvoicePaidEvent < Sequent::Core::Event
  attrs date_paid: Date
end
```

## EventHandlers

### Projectors

Projectors are registered with the EventStore and will be notified if an Event happened, so the view model (projection) can be updated.

```ruby
class InvoiceProjector < Sequent::Core::Projector
  on InvoicePaidEvent do |event|
    update_record(InvoiceRecord, event) do |record|
      record.pay_date = event.date_paid
    end
  end
end
```

Sequent currently supports updating the view model using ActiveRecord out-of-the-box.
See the `Sequent::Core::RecordSessions::ActiveRecordSession` if you want to implement another view model backend.

### Workflows

Workflows are registered with the Eventstore and will be notified if an Event happened, so a new command could be executed.

```ruby
class AccountWorkflow < Sequent::Core::Workflow
  on EmailClaimed do |event|
    execute_commands RegisterAccountForClaimedEmail.new(event)
  end
end
```

## EventStore

The EventStore is where the Events go. As a user you only have to configure the EventStore, Sequent takes care of the rest.
The EventStore is configured and accessible via the configuration.

```ruby
Sequent.configure do |config|
  config.record_class = Sequent::Core::EventRecord # configured by default but can be overridden
  config.event_handlers = [MyEventHandler.new]     # put your event handlers here
end

Sequent.configuration.event_store
```

## Aggregates

Aggregates are you top level domain classes that will execute the 'business logic'. Aggregates are called by
the CommandHandlers.

```ruby
class Invoice < Sequent::Core::AggregateRoot
  def initialize(params)
    apply InvoiceCreatedEvent, params
  end

  def pay(date, amount)
    raise "not enough paid" if @total_amount > amount
    apply InvoicePaidEvent, date_paid: date
  end

  on InvoiceCreatedEvent do |event|
    @total_amount = event.total_amount
  end

  on InvoicePaidEvent do |event|
    @date_paid = event.date_paid
  end

end
```

Event sourced application separates the business logic (in this case the check for the amount paid) with updating the state.
Since event sourced applications rebuild the model from the events, the state needs to be replayed but not your business rules.

## ValueObjects

Value objects, like commands, use ActiveModel for validations.

```ruby
class Country < Sequent::Core::ValueObject
  validate_presence_of :code, :name
  attrs code: String, name: String
end

class Address < Sequent::Core::ValueObject
  attrs street: String, country: Country
end
```

Sequent will automatically add validators in `Sequent::Core::ValueObject`s for frequently used classes like:

* Date
* DateTime
* Integer
* Boolean

Validation is automatically triggered when adding `ValueObject`s to Commands.

## Snapshotting

Snapshotting is an optimization where the aggregate's state is saved in the event stream. With snapshotting the state of an aggregate can be restored from a snapshot rather than by replaying all of its events.

Sequent supports snapshots on aggregates that call `enable_snapshots` with a default threshold. In general it is recommended to keep the threshold low, to surface possible snapshot bugs sooner.

```ruby
class MyAggregateRoot < Sequent::Core::AggregateRoot
  enable_snapshots default_threshold: 30
end
```

To adjust the threshold of individual aggregates you can update its `StreamRecord`.

Snapshots can be taken with a `SnapshotCommand`. For example by a Rake task.

```ruby
namespace :snapshot do
  task :take_all do
    catch (:done) do
      while true
        command_service.execute_commands Sequent::Core::SnapshotCommand.new(limit: 10)
      end
    end
  end
end
```

# Testing

Sequent adds some test helpers to help test your event sourced application. Only RSpec is supported at the moment.
The use of these modules are documented in the source code.

```ruby
require 'sequent/test'

RSpec.configure do |c|
  c.include Sequent::Test::CommandHandlerHelpers
  c.include Sequent::Test::WorkflowHelpers
  c.include Sequent::Test::EventStreamHelpers # FactoryGirl is required for these helpers.
end
```

It's best to scope inclusion of `CommandHandlerHelpers` to your command handler specs and `WorkflowHelpers` to your workflows.

# Contributing

Fork and send pull requests

# Releasing

Change the version in `lib/version.rb`. Commit this change.

Then run `rake release`. A git tag will be created and pushed, and the new version of the gem will be pushed to rubygems.

## Running the specs
If you wish to make changes to the `sequent` gem you can use `rake
spec` to run the tests. Before doing so you need to create a postgres
user and database first:

```sh
createuser -D -s -R sequent
createdb sequent_spec_db -O sequent
bundle exec rake db:create
```

The data in this database is deleted every time you run the specs!



# License

Sequent is released under the MIT License.
