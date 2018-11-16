---
title: EventStream
---

An EventStream is an ordered stream of [Events](events.html). Or in other words, an EventStream contains
the ordered state changes of an [AggregateRoot](aggregate-root.html). In Sequent EventStream's are bound
to a single AggregateRoot.

In Sequent EventStreams are stored in the [stream_records](event_store.html#stream_records) table automatically.

