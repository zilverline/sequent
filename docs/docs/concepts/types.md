---
title: Types
---

In Sequent events are stored as JSON in the event store. To be able to serialize and deserialize to the correct
types you are required to specify the type of an attribute.

This also gives Sequent the possibility to check if the attributes
in for instance the [Commands](command.html) and [ValueObject](value-object.html) are of the correct type.

Out of the box Sequent supports the following types:

1. String: `attrs name: String`
2. Integer: `attrs counter: Integer`
3. Date: `attrs created_at: Date`
4. DateTime: `attrs created_at: DateTime`
5. Boolean: `attrs confirmed: Boolean`
6. Symbol: `attrs user_type: Symbol`
7. Custom ValueObjects: `attrs address: Address`
8. Lists: `attrs names: array(String)`

