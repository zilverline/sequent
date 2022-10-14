---
title: Reference Guide
---

This guide gives an overview of the concepts which form the foundation of Sequent.
Most of these concepts are not specific to Sequent, but applicable to all
CQRS and event sourced applications.

## Basic flow

To illustrate the basic flow of an Sequent powered application let's use
creating a User from a webapplication as example:

1. Webapp binds form elements to a `CreateUser` [Command](concepts/command.html)
2. Webapp passes the Command to the [CommandService](concepts/command-service.html)
3. The CommandService [validates](concepts/validations.html) the Command
4. When the Command is valid the CommandService calls the registered [CommandHandlers](concepts/command-handler.html)
5. The CommandHandler creates the User as [AggregateRoot](concepts/aggregate-root.html) and stores it in the EventStore using the [AggregateRepository](concepts/aggregate-repository.html)
6. When the CommandHandler is finished the CommandService queries all affected AggregateRoots for new [Event](concepts/event.html) and stores them in the EventStore
7. All Events are propagated to registered [Projectors](concepts/projector.html)
8. The Projectors update their Projections accordingly.

**Good to know:** Points 1,2,5,8 are the steps you as programmer need to implement. Sequent takes case of the rest.
{: .notice--info}

This is basically how you do stuff in Sequent. Please checkout all concepts to get a complete overview.

## Concepts regarding your Domain:

- [AggregateRoot](concepts/aggregate-root.html)
- [Events](concepts/event.html)
- [CommandHandlers](concepts/command-handler.html)
- [AggregateRepository](concepts/aggregate-repository.html)
- [Commands](concepts/command.html)
- [ValueObject](concepts/value-object.html)
- [Types](concepts/types.html)
- [Validations](concepts/validations.html)
- [Snapshotting](concepts/snapshotting.html)
- [CommandService](concepts/command-service.html)

## Concepts mostly used by clients, like a webapp, of your application

- [Configuration](concepts/configuration.html)
- [Projectors](concepts/projector.html)
- [Workflow](concepts/workflow.html)
- [Migrations](concepts/migrations.html)

## In depth details

- [Snapshotting](concepts/snapshotting.html)
- [EventStore](concepts/event_store.html)

## Miscellaneous

- [GDPR](concepts/gdpr.html)
