---
title: Modelling your Domain in Sequent
---

## A tour of the `Post` Aggregate

The app we generated in [Getting Started](/docs/getting-started.html) comes with an example `Post` aggregate. In this guide we will take a quick look at Sequent's directory structure, go over some of the concepts used in Sequent by expanding on `Post` and create our very own `Comment` aggregate.

### Directory structure

Let's have a look at the general directory structure of a generated sequent project. If something doesn't make sense right away, bear with us because we will walk through folders these one by one in the rest of this article.

```bash
app/           # Non-domain application logic
  projectors/  # Subscribe to events and write to records
  records/     # Ephemeral view tables (ActiveRecord models)
config/        # Configurations to glue everything together
db/            # Database management and configuration
lib/           # Contains your domain logic
  post/        # Aggregate roots define the namespaces
spec/          # Tests for your application
```

Zooming in on the `lib` folder reveals the domain and most import concepts of the app:

```bash
post/                      # Files are grouped by aggregate root
  commands.rb              # All post command go here
  events.rb                # All post events go here
  post_command_handler.rb  # Subscribes to post commands and dispatches post events
  post.rb                  # The aggregate root
post.rb                    # Requires the entire aggregate root
```

### Adding a command

Changes to state start by executing a command. Commands are quite simple classes containing some attributes and attribute validations. Looking at `lib/post/commands.rb` we have one command:

```ruby
class AddPost < Sequent::Command
  attrs author: String, title: String, content: String
  validates_presence_of :author, :title, :content
end
```

Let's add a `PublishPost` command to take our `Post` from draft to published. The command will look like this:

```ruby
class PublishPost < Sequent::Command
  attrs publication_date: DateTime
  validates_presence_of :publication_date
end
```

We only need the `publication_date` attribute. Commands always target an aggregate, so we already know what to change by its `aggregate_id`. We could set a `publish` flag, but the event already communicates this intent.

_Learn all about commands in the [Command](/docs/concepts/command.html) concept guide._
{: .notice}

### Handling our new command

The `PostCommandHandler` subscribes to `Post` commands and calls the domain (i.e. the `Post` aggregate root). We can see this happening for `AddPost`:

```ruby
class PostCommandHandler < Sequent::CommandHandler
  on AddPost do |command|
    repository.add_aggregate Post.new(command)
  end
end
```

Because we are adding a new aggregate `add_aggregate` is called with `Post.new(command)` as its argument. The actual business logic of what `Post` looks like is contained in the aggregate root.

We can add our own `on` block below the `AddPost` one:

```ruby
on PublishPost do |command|
  do_with_aggregate(command, Post) do |post|
    post.publish(command.publication_date)
  end
end
```

Sequent retrieves the post for us and we call the (to be defined) `publish` method on the returned `Post` instance.

_Learn all about command handlers in the [CommandHandler](/docs/concepts/command-handler.html) concept guide._
{: .notice}

### The Aggregate Root

In `lib/post/post.rb` we find the aggregate root. This class encapsulates your business logic. Events are applied to instances of `Post` to give it its current state. We can see here that create a new `Post` will apply multiple events. Besides `PostAdded` we're also applying events to change the author, title and content. You might be tempted to group all those fields in one event, which can be a good idea if those fields always change together. We're using multiple events to emphasise that a single command does not alway correlate to a single event.

```ruby
class Post < Sequent::AggregateRoot
  def initialize(command)
    super(command.aggregate_id)
    apply PostAdded
    apply PostAuthorChanged, author: command.author
    apply PostTitleChanged, title: command.title
    apply PostContentChanged, content: command.content
  end

  # ...
end
```

Let's define how the domain should behave when receiving our new `PublishPost` command. Below the initialize method add:

```ruby
def publish(publication_date)
  fail PostAlreadyPubishedError if @publication_date.any?
  apply PostAdded
end
```

_Learn all about aggregate roots in the [AggregateRoot](/docs/concepts/aggregate-root.html) concept guide._
{: .notice}
