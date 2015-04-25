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

# Getting started

    gem install sequent

    require 'sequent'

    Sequent.configure do |config|
      config.event_handlers = [MyEventHandler.new]
      config.command_handlers = [MyCommandHandler.new]
    end

    Sequent.command_service.execute_commands MyCommand.new(...)

# Contributing

Fork and send pull requests

Run specs via `rspec`

# Tutorial

See the [sequent example app](https://github.com/zilverline/sequent-examples)

# Reference Guide

Sequent provides the following concepts from a CQRS and an event sourced application:

* Commands
* CommandService
* CommandHandlers
* AggregateRepository
* Events
* EventHandlers
* EventStore
* Aggregates
* ValueObjects

## Commands
Commands are the instructions typically initiated by the users, for instance by submitting forms.
Good practive is to give them descriptive names like `PayInvoiceCommand`.
Commands in sequent use ActiveModel for validations.

    class PayInvoiceCommand < Sequent::Core::UpdateCommand
      validates_presence_of :pay_date
      attrs pay_date: Date, amount: Integer
    end

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

    command = PayInvoiceCommand.new(aggregate_id: "10", pay_date: Date.today, amount: 100)
    Sequent.command_service.execute command

## CommandHandlers

CommandHandlers are responsible to interpreting the command and sending the correct message to an Aggregate, or in some
cases create a new Aggregate and store it in the AggregateRepository.

    class InvoiceCommandHandler < Sequent::Core::BaseCommandHandler
      on PayInvoiceCommand do |command|
        do_with_aggregate(command, Invoice) { |invoice| invoice.pay(command.pay_date, command.amount) }
      end
    end

## AggregateRepository

Repository for aggregates. Implements the Unit-Of-Work and Identity-Map patterns
to ensure each aggregate is only loaded once per transaction and that you always get the same aggregate instance back.

On commit all aggregates associated with the Unit-Of-Work are queried for uncommitted events. After persisting these events
the uncommitted events are cleared from the aggregate.

The repository is keeps track of the Unit-Of-Work per thread, so can be shared between threads.

    AggregateRepository.new(Sequent.config.event_store)

## Events

Events describe what happened in the application. Events, like commands, have descriptive names in past tense e.g. InvoicePaidEvent

    class InvoicePaidEvent < Sequent::Core::Event
      attrs date_paid: Date
    end

## EventHandlers

EventHandlers are registered with the EventStore and will be notified if an Event happened, for instance updating the view model.

    class InvoiceEventHandler < Sequent::Core::BaseEventHandler
      on InvoicePaidEvent do |event|
        update_record(InvoiceRecord, event) do |record|
          record.pay_date = event.date_paid
        end
      end
    end

Sequent currently supports updating the view model using ActiveRecord out-of-the-box.
See the `Sequent::Core::RecordSessions::ActiveRecordSession` if you want to implement another view model backend.

## EventStore

The EventStore is where the Events go. As a user you only have to configure the EventStore, Sequent takes care of the rest.
The EventStore is configured and accessible via the configuration.

    Sequent.configure do |config|
      config.record_class = Sequent::Core::EventRecord # configured by default but can be overridden
      config.event_handlers = [MyEventHandler.new]     # put your event handlers here
    end

    Sequent.configuration.event_store

## Aggregates

Aggregates are you top level domain classes that will execute the 'business logic'. Aggregates are called by
the CommandHandlers.

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

Event sourced application separates the business logic (in this case the check for the amount paid) with updating the state.
Since event sourced applications rebuild the model from the events, the state needs to be replayed but not your business rules.

## ValueObjects

Value objects, like commands, use ActiveModel for validations.

    class Country < Sequent::Core::ValueObject
      validate_presence_of :code, :name
      attrs code: String, name: String
    end

    class Address < Sequent::Core::ValueObject
      attrs street: String, country: Country
    end

Sequent will automatically add validators in `Sequent::Core::ValueObject`s for frequently used classes like:

* Date
* DateTime
* Integer
* Boolean

Validation is automatically triggered when adding `ValueObject`s to Commands.

# License

Sequent is released under the MIT License.
