---
title: ValueObject
---

ValueObjects are convenience objects that can be used to group certain attributes that
are always used together. ValueObjects can be nested.
A ValueObject must inherit from `Sequent::ValueObject`.

An example of a ValueObject is for instance an address.

```ruby
class Address < Sequent::ValueObject
  attrs line_1: String, line_2: String, city: String, country_code: String
  validates_presence_of: :line_1, :city, :country_code
end
```
