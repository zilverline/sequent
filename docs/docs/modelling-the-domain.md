---
title: Modelling your Domain in Sequent
---

## A tour of the `Account` Aggregate

The app we generated in [1.1 Getting Started](/docs/getting-started.html) comes with an example `Account` aggregate. In this guide we will go over some of the concepts used in Sequent by looking at `Account` and then creating our own aggregate.

### Commands

Everything starts with a command. Looking at `lib/account/commands.rb` we have one command: `AddAccount`.

### The Aggregate Root

In `lib/account/account.rb` we find the aggregate root.
