---
title: Modelling your Domain in Sequent
---

## A tour of the `Post` Aggregate

The app we generated in [1.1 Getting Started](/docs/getting-started.html) comes with an example `Post` aggregate. In this guide we will go over some of the concepts used in Sequent by looking at `Post` and then creating our own aggregate.

### Commands

Everything starts with a command. Looking at `lib/post/commands.rb` we have one command: `AddPost`.

### The Aggregate Root

In `lib/post/post.rb` we find the aggregate root.
