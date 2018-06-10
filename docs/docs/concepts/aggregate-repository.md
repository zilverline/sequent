---
title: AggregateRepository
---

The AggregateRepository is the interface for accessing Aggregates in the EventStore.

The AggregateRepository is typically used in [CommandHandlers](command-handler.html) to load and add [AggregateRoots](aggregate-root.html).

You can access the AggregateRepository via `Sequent.aggregate_repository`
