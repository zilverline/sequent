---
title: Getting started with Sequent
---

## Guide assumptions

This guide is designed for beginners who want to get started with a Sequent application from scratch. It does not assume that you have any prior experience with Sequent.

Sequent uses design patterns from DDD (Domain-Driven Design) like CQRS and Event Sourcing. Some basic familiarity with these principles is expected but you don't need to be an expert. For more information on this we might refer to some DDD resources in the guide.

## What is Sequent?

Sequent is a CQRS and Event Sourcing framework for Ruby. It enables you to capture all changes to an application state as a sequence of events, rather than just storing the current state. This has some advantages:

- Time travel back to any prior state. i.e. for debugging.
- Get auditability and traceability for free.
- Backfill new tables/columns by replaying existing events.
- Easy to reason about events with other stakeholders (Ubiquitous Language)

To read up on some of these concepts we recommend Martin Fowler's wiki:

- [CQRS (Command Query Responsibility Segregation)](https://martinfowler.com/bliki/CQRS.html)
- [Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)
- [Ubiquitous Language](https://martinfowler.com/bliki/UbiquitousLanguage.html)

## Creating a new Sequent project

The best way to read this guide is to follow it step by step. All steps are essential to run this example application and no additional code or steps are needed.

By following along with this guide, you'll create a Sequent project called blog, a (very) simple weblog. Before you can start building the application, you need to make sure that you have Sequent itself installed.

### Installing Sequent

Before you install Sequent, you should check to make sure that your system has the proper prerequisites installed. These include Ruby and PostgreSQL.

#### Ruby

Verify that you have a current version of Ruby installed:

```bash
$ ruby -v
ruby 2.5.0p0 (2017-12-25 revision 61468) [x86_64-darwin17]
```

Sequent require Ruby version 2.3.7 or later. If the version number returned is lower, you'll need to upgrade your Ruby version. For managing Ruby versions we recommend [rbenv](https://github.com/rbenv/rbenv).

#### Postgres

You will also need to have the PostgreSQL database server installed. Verify that you have a current version of PostgresQL installed:

```bash
$ pg_config --version
PostgreSQL 9.4.14
```

Sequent requires PostgreSQL version 9.4 or later. For installation instructions refer to your OS or see [postgresql.org](https://www.postgresql.org)

#### Sequent

Install Sequent using RubyGems:

```bash
$ gem install sequent
```

Verify that sequent was installed correctly by running the command:

```bash
$ sequent
Please specify a command. i.e. `sequent new myapp`
```

### Creating the Blog application

Sequent offers generators to help you develop your application without having to set up the plumbing of the system yourself. We can generate a new Sequent application using `sequent`:

```bash
$ sequent new blog

Success!

...
```

This will create your new Sequent application in the `blog` directory and guide you toward your next steps. Don't rush in yet, we will follow these steps in a minute. Let's switch to the blog application folder:

```bash
$ cd blog
```

We can see the `blog` directory was generated with a number of files and folders that form the basic structure of a sequent application:

```bash
$ ls -1
Gemfile
Gemfile.lock
Rakefile
app
blog.rb
config
db
lib
spec
```

Now let's finish our setup by installing the gems and preparing the database:

```bash
bundle install
bundle exec rake sequent:db:create
RACK_ENV=test bundle exec rake sequent:db:create
bundle exec rake sequent:db:create_view_schema
bundle exec rake sequent:migrate:online
bundle exec rake sequent:migrate:offline
```

If your database already exists and you just need to create the event_store schema and the view_schema then do:
```bash
bundle exec rake sequent:db:create_event_store
bundle exec rake sequent:db:create_view_schema
bundle exec rake sequent:migrate:online
bundle exec rake sequent:migrate:offline
```

Your Sequent app is ready to rock!

## Hello, Sequent!

Sequent does not come with a web framework included. We'll look into bringing it all together in a later guide. As such a real "hello world" is outside the scope of this
guide. What we can do is demonstrate our business logic is working. We'll examine our example domain in a minute.
Let's first take a look at our (generated) specs:

- `spec/lib/post/post_command_handler_spec.rb`: Here we test that when a command is given, certain events will occur.
- `spec/app/projectors/post_projector_spec.rb`: Here we test that when an event occurs, the projector updates the view records.

Now we run the specs to ensure we have a working system:

```bash
$ bundle exec rspec
...

Finished in 0.2 seconds (files took 1.4 seconds to load)
3 examples, 0 failures
```

The specs are green and we are ready to dive into the domain! Let's continue with: [1.2 Modelling the domain](/docs/modelling-the-domain.html)
