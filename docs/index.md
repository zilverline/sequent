---
sidebar: false
title: Sequent 3.0
---
Sequent is a CQRS and event sourcing framework (ES) written in Ruby. This site is intended
to help you learn and develop CQRS / ES applications in Ruby (using Sequent).
Sequent **focusses** on the **domain logic** of your application. It is web framework agnostic.
You can use it with Rails, Sinatra or whatever framework you like.

There are several guides available

## Getting Started
New to Sequent? [Getting Started](/docs/getting-started.html) the place to start.

## Concepts

### AggregateRoot
An [AggregateRoot](/docs/concepts/aggregate-root.html) is the class that encapsulates your domain logic. Your aggregates form the heart of your application.

### Event
[Events](/docs/concepts/event.html) are domain events that are significant to your domain. An AggregateRoot is basically a stream of Events.

### Command
[Commands](/docs/concepts/command.html) form the API of your domain. They are simple data objects
with descriptive names describing the intent of your command. E.g. `SendInvoice`.

### CommandHandler
Commands are handled by [CommandHandlers](/docs/concepts/command-handler.html). Based on the incoming Command the CommandHandler decides what to do.

### Projector
[Projectors](/docs/concepts/projector.html) listen to Events. They are responsible for update the Projections in the view schema.

### Workflow
[Workflows](/docs/concepts/workflow.html) also listen to Events. They are typically used for anything else you want to do with events. (E.g. execute another command).

### AggregateRepository
The [AggregateRepository](/docs/concepts/aggregate-repository.html) is the interface to the event store. Use this object to load and store AggregateRoots.

### CommandService
The [CommandService](/docs/concepts/command-service.html) is the interface for executing commands. The CommandService will than call you CommandHandlers in order to get things done.


## Further reading

* [Event sourcing](http://martinfowler.com/eaaDev/EventSourcing.html)
* [Lars and Bob's presentation at GOTO Amsterdam](http://gotocon.com/dl/goto-amsterdam-2013/slides/BobForma_and_LarsVonk_EventSourcingInProductionSystems.pdf)
* [Erik's blog series](http://blog.zilverline.com/2011/02/10/towards-an-immutable-domain-model-monads-part-5/)
* [Simple CQRS example by Greg Young](https://github.com/gregoryyoung/m-r)
* [Google](http://www.google.nl/search?ie=UTF-8&q=cqrs+event+sourcing)

## License

Sequent is released under the MIT License.
