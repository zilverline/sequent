---
title: Modelling the domain in Sequent
toc: true
toc_sticky: true
classes: []
---

The app we generated in [Getting Started](/docs/getting-started.html) comes with an example `Post` aggregate. In this guide we will take a
quick look at Sequent's directory structure, go over some of the concepts used in Sequent by expanding on `Post`, and
create our very own `Author` aggregate.

## Example `Post` aggregate

### Directory structure

Let's have a look at the general directory structure of a generated Sequent project. If something doesn't make sense
right away, bear with us because we will walk through these folders one by one in the rest of this article.

```bash
app/           # Non-domain application logic
  projectors/  # Subscribe to events and write to records
  records/     # Ephemeral view tables (ActiveRecord models)
config/        # Configurations to glue everything together
db/            # Database management and configuration
lib/           # Contains your domain logic
spec/          # Tests for your application
```

Zooming in on the `lib` folder reveals the domain and most important concepts of the app:

```bash
post/                      # Files are grouped by aggregate root
  commands.rb              # All post commands go here
  events.rb                # All post events go here
  post_command_handler.rb  # Subscribes to post commands and dispatches post events
  post.rb                  # The aggregate root
post.rb                    # Requires the entire aggregate root
```

### Commands

Changes to state start by executing a command. Commands are quite simple classes containing some attributes and
attribute validations. Looking at `lib/post/commands.rb`, we have one command:

```ruby
class AddPost < Sequent::Command
  attrs author: String, title: String, content: String
  validates_presence_of :author, :title, :content
end
```

_Learn all about commands in the [Command](/docs/concepts/command.html) Reference Guide._
{: .notice}

### Handling commands

The `PostCommandHandler` in `lib/post/post_command_handler.rb` subscribes to `Post` commands and calls the domain (i.e.
the `Post` aggregate root). We can see this happening for `AddPost`:

```ruby
class PostCommandHandler < Sequent::CommandHandler
  on AddPost do |command|
    repository.add_aggregate Post.new(command)
  end
end
```

Because we are adding a new aggregate, `add_aggregate` is called with `Post.new(command)` as its argument. The actual
business logic of what `Post` looks like is contained in the aggregate root, which we'll look at in the next paragraph.

You are free to define your own signature of the constructor. In the example we chose to pass the command as argument,
but nothing prevents you to define it using the separate attributes.

_Learn all about command handlers in the [CommandHandler](/docs/concepts/command-handler.html) Reference Guide._
{: .notice}

### Aggregate Root

In `lib/post/post.rb` we find the aggregate root. This class encapsulates your business logic. Events are applied to
instances of `Post` to give it its current state. We can see here that creation of a new `Post` will apply multiple
events. Besides `PostAdded` we're also applying events to change the author, title and content. You might be tempted to
group all those fields in one event, which can be a good idea if those fields always change together. We're using
multiple events to emphasise that a single command does not always correlate to a single event.

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

_Learn all about aggregate roots in the [AggregateRoot](/docs/concepts/aggregate-root.html) Reference Guide._
{: .notice}

### Events

In `lib/post/events.rb` we have the events defined which are used in the aggregate root:

```ruby
class PostAdded < Sequent::Event
end

class PostAuthorChanged < Sequent::Event
  attrs author: String
end

class PostTitleChanged < Sequent::Event
  attrs title: String
end

class PostContentChanged < Sequent::Event
  attrs content: String
end

```

Events contain all the state changes on an AggregateRoot. These events are stored in the database in the `event_records`
table as JSON.

_Learn all about events in the [Event](/docs/concepts/event.html) Reference Guide._
{: .notice}

## Publishing a Post

We have now gone through the generated example files.

Lets expand Post by adding functionality to take our `Post` from draft to published.

### Test setup

Add the following test case to the `PostCommandHandler` tests in `spec/lib/post/post_command_handler_spec.rb`:

```ruby
  it 'publishes a post' do
    given_events PostAdded.new(aggregate_id: aggregate_id, sequence_number: 1)

    when_command PublishPost.new(aggregate_id: aggregate_id, publication_date: Date.current.to_s)
    then_events(
      PostPublished.new(aggregate_id: aggregate_id, sequence_number: 1, publication_date: Date.current.to_s)
    )
  end
```

This test will fail as our code is missing the `PublishPost` command, `PostPublished` event and the command handling in
`PostCommandHandler`.

### Publish Post command

Let's add a `PublishPost` command, the command will look like this:

```ruby
class PublishPost < Sequent::Command
  attrs publication_date: DateTime
  validates_presence_of :publication_date
end
```

We only need the `publication_date` attribute. Commands always target an aggregate, so we already know what to change by
its `aggregate_id`. We could set a `publish` flag, but the event already communicates this intent.

### Handling publish Post command

We add our own `on` block below the `AddPost` block in `lib/post/post_command_handler.rb` to handle the `PublishPost`
command:

```ruby
on PublishPost do |command|
  do_with_aggregate(command, Post) do |post|
    post.publish(command.publication_date)
  end
end
```

Sequent retrieves the post for us and we call the (to be defined) `publish` method on the returned `Post` instance.

### Post aggregate Root

Let's define how the domain should behave when receiving our new `PublishPost` command. In `lib/post/post.rb`, below the
initialize method add:

```ruby
class PostAlreadyPublishedError < StandardError; end

def publish(publication_date)
  fail PostAlreadyPublishedError if @publication_date.present?

  apply PostPublished, publication_date: publication_date
end
```

In Sequent you execute / enforce your business rules in these methods **before** applying events.

### Post published event

In `lib/post/post.rb` we just applied the `PostPublished` event. We need to define this event in `lib/post/events.rb`,
add the following:

```ruby
class PostPublished < Sequent::Event
  attrs publication_date: Date
end
```

### Handling event

Back in the aggregate root, we handle the `PostPublished` event. Add the following to the class `Post` in lib/post/post.rb`:

```ruby
on PostPublished do |event|
  @publication_date = event.publication_date
end
```

With this latest change, the test case in `post_command_handler_spec.rb` will succeed. The domain is now able to handle
post publishing.


## Adding an Author

In this guide, we will 'upgrade' `Author` to its own Aggregate Root. This means we need to add new files defining the
`Author` Aggregate Root, and make some changes to the `Post` commands and events, i.e. using the author `aggregate_id`
instead of an author String.

### Test setup

Create `spec/lib/author/author_command_handler_spec.rb` with:

```ruby
require_relative '../../spec_helper'
require_relative '../../../lib/author'
require_relative '../../../lib/usernames'

describe AuthorCommandHandler do
  before :each do
    Sequent.configuration.command_handlers = [AuthorCommandHandler.new]
  end

  context AddAuthor do
    it 'creates a user when valid input'
    it 'fails if the username already exists'
    it 'ignores case in usernames'
  end
end
```

There might be more edge cases but for now this is sufficient.

### General setup

Let's create the necessary classes in order to get the test to 'green'.

We will stick to Sequent's suggested directory structure, so we will end up with something like this:

```bash
blog.rb
lib/           # Contains your domain logic
  author.rb    # Requires all author/*.rb
  usernames.rb # Requires all usernames/*.rb
  author/      # Contains the author related domain classes
    author.rb
    events.rb
    commands.rb
    author_command_handler.rb
  usernames/   # Contains the usernames related domain classes
    usernames.rb
    events.rb
```

#### Author aggregate root

Create `lib/author/author.rb` with:

```ruby
class Author < Sequent::AggregateRoot
end
```

#### Author command

Let's create the command to add an `Author`. Create `lib/author/commands.rb` with:

```ruby
class AddAuthor < Sequent::Command
  attrs name: String, email: String
  validates_presence_of :name, :email
end
```

#### Author command handler

Create `lib/author/author_command_handler.rb` and add the new `AuthorCommandHandler` class:

```ruby
class AuthorCommandHandler < Sequent::CommandHandler
end
```

Require the new `Author` aggregate by adding the following to `blog.rb`:
```ruby
require_relative 'lib/author'
```

Create `lib/author.rb` to require the files in `lib/author`:
```ruby
require_relative 'author/commands'
require_relative 'author/author'
require_relative 'author/author_command_handler'
```

### Usernames aggregate root

One of the things we need to do, is to check the uniqueness of the Author's email. Since we only store the events in the
event store, we can not simply add a unique constraint to ensure uniqueness. A common solution to this problem is to
create yet another Aggregate responsible for maintaining all usernames.
We will name this Aggregate `Usernames`. Since it needs to ensure uniqueness, there can be only one instance of this.
In order to achieve that, we create the Usernames class as a [Singleton](https://refactoring.guru/design-patterns/singleton).

Create `lib/usernames/usernames.rb` with:

```ruby
class Usernames < Sequent::AggregateRoot
  class UsernameAlreadyRegistered < StandardError; end

  # We can generate and hardcode the UUID since there is only one instance
  ID = "85507d60-8645-4a8a-bdb8-3a9c86a0c635"

  def self.instance(id = ID)
    Sequent.configuration.aggregate_repository.load_aggregate(id)
  rescue Sequent::Core::AggregateRepository::AggregateNotFound
    usernames = Usernames.new(id)
    Sequent.aggregate_repository.add_aggregate(usernames)
    usernames
  end
end
```

Require the new `Usernames` aggregates by adding the following to `blog.rb`:
```ruby
require_relative 'lib/usernames'
```

Create `lib/usernames.rb` to require the files in `lib/usernames`:
```ruby
require_relative 'usernames/usernames'
```

We can now obtain the `Usernames` Aggregate by invoking `Usernames.instance`. Next thing we want to do is create the
`AuthorCommandHandler` and add an Author.

### Author command handler
When we run the tests in `spec/lib/author/author_command_handler_spec.rb`, all are marked as `Pending: Not yet
implemented`. Before we can go any further, we need to think about what kind of Events we are interested in.
What do we want to know in this case? When registering our very first `Author`, it will not only create the Author,
but also create our `Usernames` Aggregate to ensure uniqueness of the usernames.

The test will read something like:
```
When i add an Author for the first time
Then the Usernames registry is created
And the username is checked for uniqueness and added to the Usernames
And the Author is created with the given name and email
```

By leveraging Sequent's test DSL we can modify the test we have created for this in
`spec/lib/author/author_command_handler_spec.rb` as follows:

```ruby
context AddAuthor do
  let(:user_aggregate_id) { Sequent.new_uuid }
  let(:email) { 'ben@sequent.io' }

  it 'creates a user when valid input' do
    when_command AddAuthor.new(aggregate_id: user_aggregate_id, name: 'Ben', email: email)
    then_events UsernamesCreated.new(aggregate_id: Usernames::ID, sequence_number: 1),
                UsernameAdded.new(aggregate_id: Usernames::ID, username: email, sequence_number: 2),
                AuthorCreated.new(aggregate_id: user_aggregate_id, sequence_number: 1),
                AuthorNameSet,
                AuthorEmailSet.new(aggregate_id: user_aggregate_id, email: email, sequence_number: 3)
  end
  it 'fails if the username already exists'
  it 'ignores case in usernames'
end
```

In Sequent (or other event sourcing libraries) you test your code by checking the applied events, and which order they
were run in. In this case we modelled the `AuthorNameSet` and `AuthorEmailSet` as separate events, since they probably
don't change together.

In more comprehensive cases we can imagine triggering other events, e.g. when the email changes, a confirmation is sent.
You should take these considerations into account when modelling your domain and defining your Events.

Let's create the necessary code to make the test pass.

#### Usernames events

Create `lib/usernames/events.rb` with:

```ruby
class UsernamesCreated < Sequent::Event
end

class UsernameAdded < Sequent::Event
end
```

and require the file by updating `lib/usernames.rb` to:
```ruby
require_relative 'usernames/events'
require_relative 'usernames/usernames'
```

As you can see the events have no attributes yet. This is not necessary to make this test pass. Sequent only looks at
the defined attributes and sets those as values on the event, in the event store. Therefore all attributes you want to
include on an event, need to be explicitly declared.

#### Update Usernames aggregate root
Update `lib/usernames/usernames.rb` to:

```ruby
class Usernames < Sequent::AggregateRoot
  class UsernameAlreadyRegistered < StandardError; end

  # We can generate and hardcode the UUID since there is only one instance
  ID = '85507d60-8645-4a8a-bdb8-3a9c86a0c635'

  def self.instance(id = ID)
    Sequent.aggregate_repository.load_aggregate(id)
  rescue Sequent::Core::AggregateRepository::AggregateNotFound
    usernames = Usernames.new(id)
    Sequent.aggregate_repository.add_aggregate(usernames)
    usernames
  end

  def initialize(id)
    super(id)
    apply UsernamesCreated
  end

  def add(username)
    apply UsernameAdded, username: username
  end
end
```

#### Author events

Create `lib/author/events.rb` with:
```ruby
class AuthorCreated < Sequent::Event
end

class AuthorNameSet < Sequent::Event
  attrs name: String
end

class AuthorEmailSet < Sequent::Event
  attrs email: String
end
```

and require the file by adding to `lib/author.rb`:
```ruby
require_relative 'author/events'
```

#### Update Author aggregate root

Update `lib/author/author.rb` to:
```ruby
class Author < Sequent::AggregateRoot
  def initialize(command)
    super(command.aggregate_id)
    apply AuthorCreated
    apply AuthorNameSet, name: command.name
    apply AuthorEmailSet, email: command.email
  end
end
```

#### Update Author command handler

Update `lib/author/author_command_handler.rb` to:
```ruby
class AuthorCommandHandler < Sequent::CommandHandler
  on AddAuthor do |command|
    Usernames.instance.add(command.email)
    repository.add_aggregate(Author.new(command))
  end
end
```

The [Author command handler test](#author-command-handler) will now pass.

### Author email constraint

For the next test case we want to assert the following:

```
Given an Author with email 'ben@sequent.io'
When I try to add another author with email 'ben@sequent.io'
Then it should fail
```

Replace the matching test case in `spec/lib/author/author_command_handler_spec.rb` to:

```ruby
it "fails if the username already exists" do
  given_events UsernamesCreated.new(aggregate_id: Usernames::ID, sequence_number: 1),
               UsernameAdded.new(aggregate_id: Usernames::ID, username: email, sequence_number: 2)
  expect {
    when_command AddAuthor.new(
      aggregate_id: Sequent.new_uuid,
      name: 'kim',
      email: 'ben@sequent.io'
    )
  }.to raise_error Usernames::UsernameAlreadyRegistered
end
```

When we run this spec we get the following error message:

```text
RuntimeError:
  Cannot find aggregate type associated with creation event {UsernamesCreated: @aggregate_id=[85507d60-8645-4a8a-bdb8-3a9c86a0c635], @sequence_number=[1], @created_at=[2024-10-09 15:56:54 +0200]}, did you include an event handler in your aggregate for this event?
```

Sequent requires us to define an event handler in the Aggregate for at least the creation event, otherwise Sequent is
not able to find an Aggregate in the repository.

So let's change our aggregates to satisfy this demand.

Add to `Usernames` in `lib/usernames/usernames.rb`:
```ruby
class Usernames < Sequent::AggregateRoot
  ...

  on UsernamesCreated do

  end
end
```

Add to `Author` in `lib/author/author.rb`

```ruby
class Author < Sequent::AggregateRoot
  ...

  on AuthorCreated do

  end
end
```

Running the test case again results in the following error:
```text
expected Usernames::UsernameAlreadyRegistered but nothing was raised
```

This is as expected, since we didn't implement anything. Let's start by enforcing uniqueness.

Change the `Usernames` aggregate as follows:

```ruby
class Usernames < Sequent::AggregateRoot
  ...

  def add(username)
    fail UsernameAlreadyRegistered if @usernames.include?(username)

    apply UsernameAdded, username: username
  end

  on UsernamesCreated do
    @usernames = Set.new
  end

  on UsernameAdded do |event|
    @usernames << event.username
  end
end
```

The `UsernameAdded` event in `lib/usernames/events.rb` needs to contain the username attribute to make the test pass:

```ruby
class UsernameAdded < Sequent::Event
  attrs username: String
end
```

The event handlers `UsernamesCreated` and `UsernameAdded` will keep track of the current usernames in a `Set`.
Whenever a new name is being added, we first check if the name does not yet exist. If it does not exist, a new event is
applied. The test case now passes successfully.


### Author email case insensitive

Let's finish up by implementing our last test to check that string case is ignored when registering an Author.

Replace the matching test case in `spec/lib/author/author_command_handler_spec.rb` to:

```ruby
it "ignores case in usernames" do
  given_events UsernamesCreated.new(aggregate_id: Usernames::ID, sequence_number: 1),
               UsernameAdded.new(aggregate_id: Usernames::ID, username: email, sequence_number: 2)
  expect {
    when_command AddAuthor.new(
      aggregate_id: Sequent.new_uuid,
      name: 'kim',
      email: 'BeN@SeQuEnT.io'
    )
  }.to raise_error Usernames::UsernameAlreadyRegistered
end
```

We change our `Usernames` aggregate to satisfy this requirement as follows in `lib/usernames/usernames.rb`:

```ruby
class Usernames < Sequent::AggregateRoot
  ...

  def add(username)
    fail UsernameAlreadyRegistered if @usernames.include?(username.downcase)

    apply UsernameAdded, username: username
  end

  ...

  on UsernameAdded do |event|
    @usernames << event.username.downcase
  end
end
```

### Adding a Post using the new Author Aggregate Root

The last thing we need to do to successfully add a post, is refactor out `Author` name, and instead use the `Author`
`aggregate_id`. This requires a few changes.

1. Change the passed command values and event attributes in test of `PostCommandHandler` in `spec/lib/post/post_command_handler_spec.rb`:
```ruby
let(:aggregate_id) { Sequent.new_uuid }
let(:author_aggregate_id) { Sequent.new_uuid }
```
```ruby
it 'creates a post' do
  when_command AddPost.new(aggregate_id: aggregate_id, author_aggregate_id: author_aggregate_id, title: 'My first blogpost', content: 'Hello World!')
  then_events(
      PostAdded.new(aggregate_id: aggregate_id, sequence_number: 1),
      PostAuthorChanged.new(aggregate_id: aggregate_id, sequence_number: 2, author_aggregate_id: author_aggregate_id),
      PostTitleChanged,
      PostContentChanged
  )
end
```

1. Update the attribute presence validation of `AddPost` in `lib/post/commands.rb`:
```ruby
class AddPost < Sequent::Command
  attrs author_aggregate_id: String, title: String, content: String
  validates_presence_of :author_aggregate_id, :title, :content
end
```

1. Update the `initialize` method and `on PostAuthorChanged` handler in `lib/post/post.rb`
```ruby
def initialize(command)
  super(command.aggregate_id)
  apply PostAdded
  apply PostAuthorChanged, author_aggregate_id: command.author_aggregate_id
  apply PostTitleChanged, title: command.title
  apply PostContentChanged, content: command.content
end
```
```ruby
on PostAuthorChanged do |event|
  @author_aggregate_id = event.author_aggregate_id
end
```

1. Update the `PostAuthorChanged` event in `lib/post/events.rb`
```ruby
class PostAuthorChanged < Sequent::Event
  attrs author_aggregate_id: String
end
```
When running the tests, they should now all pass.


## Summary

In this guide we:

1. Explored the generated `Post` AggregateRoot.
2. Added new functionality to publish a `Post`.
3. Added a new Aggregate `Author` and `Usernames` and showed how Aggregates can depend on each other.
4. Explored how to add tests in Sequent in order to test the domain.

In this guide we mainly focussed on the domain. In the [next guide](/docs/building-a-web-application.html) we will take
it a step further and see how can actually build a web application that our Authors can use. We will learn how to
initialize and set up Sequent with Sinatra, learn about [Projectors](/docs/concepts/projector.html) and see how Sequent
deals with migrations.
