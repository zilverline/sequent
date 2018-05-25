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
An [AggregateRoot](/docs/concepts.html#AggregateRoot) is the class that encapsulates your domain logic. Your aggregates form the heart of your application.


### Event
[Events](/docs/concepts.html#Event) are domain events that are significant to your domain. An AggregateRoot is basically a stream of Events.


### Command
[Commands](/docs/concepts.html#Command) form the API of your domain.

### CommandHandler
Commands are handled by [CommmandHandlers](/docs/concepts.html#CommandHandler). Based on the incoming Command the CommandHandler decides what to do.

### Projector
[Projectors](/docs/concepts.html#Projector) respond to Events. They are responsible for update the Projections in the view schema.

### Workflow
[Workflows](/docs/concepts.html#Workflow) also respond to Events. They are typically used for anything else you want to do with events. (E.g. execute another command).


## Further reading

* [Event sourcing](http://martinfowler.com/eaaDev/EventSourcing.html)
* [Lars and Bob's presentation at GOTO Amsterdam](http://gotocon.com/dl/goto-amsterdam-2013/slides/BobForma_and_LarsVonk_EventSourcingInProductionSystems.pdf)
* [Erik's blog series](http://blog.zilverline.com/2011/02/10/towards-an-immutable-domain-model-monads-part-5/)
* [Simple CQRS example by Greg Young](https://github.com/gregoryyoung/m-r)
* [Google](http://www.google.nl/search?ie=UTF-8&q=cqrs+event+sourcing)

## License

Sequent is released under the MIT License.
