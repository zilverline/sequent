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

## A typical Execution flow
Commands are the instructions typically initiated by the users (by submitting forms).

For instance: `PayInvoiceCommand`. A typical execution flow is as follows:

* User posts form
* `PayInvoiceCommand` is created and executed by the `CommandService`
* `CommandService` finds appropriate `CommandHandler` which handles the command
* `CommandHandler` loads the correct `AggregateRoot` and calls the correct method, in this case `Invoice.pay_invoice`
* `Invoice` checks if `pay_invoice` can be handled and if so raises and applies the correct events. In this case `InvoicePaidEvent`.
* `CommandHandler` sends all events that happened (`AggregateRoot.uncommitted_events`) to the registered `EventHandlers`
* `EventHandlers` handle the incoming events (typically updating view state)

# Getting started

```
gem install sequent
```

```
require 'sequent'
```

# Contributing

Fork and pull

# Examples

See [sequent examples](https://github.com/zilverline/sequent-examples)

# License

Sequent is released under the MIT License.
