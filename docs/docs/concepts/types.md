---
title: Types
---

In Sequent events are stored as JSON in the event store. To be able to serialize and deserialize to the correct
types you are required to specify the type of an attribute.

This also gives Sequent the possibility to check if the attributes
in for instance the [Commands](command.html) and [ValueObject](value-object.html) are of the correct type.

Out of the box Sequent supports the following types:

1. [String](#string)
1. [Integer](#integer)
1. [Date](#date)
1. [DateTime](#datetime)
1. [Symbol](#symbol)
1. [ValueObjects](#valueobjects)
1. [Lists](#lists)

### String

Usage: `attrs name: String`

Valid strings are `nil` or of type `String`.
There are some invalid characters like `"\0000"` postgres can't handle.

When a String is considered invalid the error code `invalid_string` is
added to the attribute in the ActiveModels `Errors` object during [validation](validations.html).

### Integer

Usage `attrs counter: Integer`

Registers the following Validation:

```
validates_numericality_of :counter, only_integer: true, allow_nil: true, allow_blank: true
```

To accommodate user input Integers passed as Strings
are parsed automatically when a Command is passed to the CommandService.

### Date:

Usage `attrs created_at: Date`

Accepts all `Date` objects. To accommodate user input valid
iso8601 date Strings are parsed automatically when
a Command is passed to the [CommandService](command-service.html).

## DateTime

Usage `attrs created_at: DateTime`

Accepts all `DateTime` objects. To accommodate user input valid
iso8601 datetime Strings are parsed automatically when
a Command is passed to the CommandService.

## Boolean:

Usage `attrs confirmed: Boolean`

Valid Booleans are `true` `false` and `nil`. To accommodate user input
the values `"true"` and `"false"` are parsed to `true` and `false`
automatically when a Command is passed to the CommandService.

## Symbol:

Usage `attrs user_type: Symbol`


## ValueObjects

Usage: `attrs address: Address`

Custom [ValueObjects](value-object.html) can contain other ValueObjects
of `attrs` of the Types described here.

## Lists

Usage: `attrs names: array(String)`

Lists can be List or any Type described here.

