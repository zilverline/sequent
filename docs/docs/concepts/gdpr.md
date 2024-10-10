---
title: GDPR
---

GDPR introduces the "right to be forgotten". Like any other datastore, an event store also needs to comply
to this regulation. Sequent does not provide this capability out of the box, but you can roll your own and choose
from several strategies. See for a lengthy discussion: [https://github.com/zilverline/sequent/issues/222](https://github.com/zilverline/sequent/issues/222){:target="_blank"}.

## Tombstoning

[Tombstoning](https://carnage.github.io/2018/10/events-are-forever) is a mechanism that applies a Tombstone Event to all aggregates belonging to that "user".

This tombstone event can than be propagated to all other aggregates, that do not belong the the "user", that also
need to "scrub" any (identifiable) data from it's event stream. For instance, a "user" added a Comment to a Blog.
Whenever the "user" invokes the right to be forgotten the Blog will be notified to scrub the Comment of the "user".

## Event deletion

Although event deletion goes against the immutable nature of an event store, this is the 'easiest' way
to comply with gdpr. To implement this you will need to keep track of which aggregates belongs to which "user".
This deletion can go hand in hand with tombstoning - all "user" aggregates can be safely deleted after a certain
grace period. You of course can't delete the Comment from the Tombstoning example since that will invalidate the Aggregate
event stream, but since it is tombstoned, the data can not be processed anymore.

