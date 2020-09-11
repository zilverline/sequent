---
title: Modelling your Domain in Sequent
---

## A tour of the `Post` Aggregate

The app we generated in [Getting Started](/docs/getting-started.html) comes with an example `Post` aggregate. In this guide we will take a quick look at Sequent's directory structure, go over some of the concepts used in Sequent by expanding on `Post` and create our very own `Author` aggregate.

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

Changes to state start by executing a command. Commands are quite simple classes containing some attributes and attribute validations. Looking at `lib/post/commands.rb`, we have one command:

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

_Learn all about commands in the [Command](/docs/concepts/command.html) Reference Guide._
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

You are free to define your own signature of the constructor. In the example we chose to pass the command as argument, but nothing prevents you to define it using the separate attributes.

We can add our own `on` block below the `AddPost` one:

```ruby
on PublishPost do |command|
  do_with_aggregate(command, Post) do |post|
    post.publish(command.publication_date)
  end
end
```

Sequent retrieves the post for us and we call the (to be defined) `publish` method on the returned `Post` instance.

_Learn all about command handlers in the [CommandHandler](/docs/concepts/command-handler.html) Reference Guide._
{: .notice}

### The Aggregate Root

In `lib/post/post.rb` we find the aggregate root. This class encapsulates your business logic. Events are applied to instances of `Post` to give it its current state. We can see here that create a new `Post` will apply multiple events. Besides `PostAdded` we're also applying events to change the author, title and content. You might be tempted to group all those fields in one event, which can be a good idea if those fields always change together. We're using multiple events to emphasise that a single command does not always correlate to a single event.

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
  apply PostPublished, publication_date: publication_date
end
```

In sequent you execute / enforce your business rules in these methods **before** applying events.

_Learn all about aggregate roots in the [AggregateRoot](/docs/concepts/aggregate-root.html) Reference Guide._
{: .notice}


### Adding the event

In `lib/post/post.rb` we just applied the `PostPublished` event. We need to define this event in `lib/post/events.rb`:

```ruby
class PostPublished < Sequent::Event
  attrs publication_date: Date
end
```

Events contain all the state changes on an AggregateRoot. These events are stored in the database in the `event_records` table as JSON.

_Learn all about events in the [Event](/docs/concepts/event.html) Reference Guide._
{: .notice}


### Adding Author

So we have gone through the generated example. In order to add Author as an Aggregate we will need to make some changes to the Commands and Events. Since we want to 'upgrade' Author to an Aggregate we need to use the `aggregate_id` instead of a author String.

But before we can add a Post we need to have an `Author`.

In `lib/author/author.rb` add:

```ruby
class Author < Sequent::AggregateRoot
end
```

So first let's create the command to add an `Author`.

In `lib/author/commands.rb` add:

```ruby
class AddAuthor < Sequent::Command
  attrs name: String, email: String
  validates_presence_of :name, :email
end
```

One of the things we need to do is to check the uniqueness of the Author's email. Since we only store the events in the event store, we can not simply add a unique constraint to ensure uniqueness. A common solution to this problem is to create yet another Aggregate responsible for maintaining all usernames.
We will name this Aggregate `Usernames`. Since it needs to ensure uniqueness there can be only one instance of this, in order to achieve that we create this class as a Singleton.

In `lib/usernames/usernames.rb` add:

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

We can now obtain the `Usernames` Aggregate by invoking `Usernames.instance`. Next thing we want to do is create a `AuthorCommandHandler` and add an Author. To ensure everything will work we start by defining our tests.

In `spec/lib/author/author_command_handler_spec.rb`

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

There might be more edge cases, but for now this is sufficient.

Let's create the necessary classes in order to get the test to 'green'.

We will stick to sequent's suggested directory structure so we will end up with something like this:

```bash
blog.rb
lib/           # Contains your domain logic
  author.rb    # Requires all author/*.rb
  usernames.rb # Requires all usernames/*.rb
  author/      # Contains the author related domain classes
    author.rb
    events.rb
    command.rb
    author_command_handler.rb
  usernames/   # Contains the usernames related domain classes
    usernames.rb
    events.rb
```

Don't forget to add to `blog.rb`:

```ruby
require_relative 'lib/author'
require_relative 'lib/usernames'
```

The `author/author_command_handler.rb`:

```ruby
class AuthorCommandHandler < Sequent::CommandHandler

end
```

The `author/commands.rb`

```ruby
class AddAuthor < Sequent::Command
  attrs name: String, email: String
  validates_presence_of :name, :email
end
```

And the `AuthorCommandHandler` to `config/initializers/sequent.rb`.

Now when we run the tests all are marked as `Pending: Not yet implemented`. Before we can go any further we need to think about what kind of Events we are interested in. What do we want to know in this case? When registering our very first `Author` it will not only create the Author, but also create our `Usernames` Aggregate to ensure uniqueness of the usernames. So the test is something like:

```
When i add an Author for the first time
Then the Usernames registry is created
And the username is checked for uniqueness and added to the Usernames
And the Author is created with the given name and email
```

By leveraging Sequent's test DSL we can create a test for this as follows:

```ruby
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
```

In Sequent (or other event sourcing libraries) you test your code by checking the applied events.
In this case we modelled the `AuthorNameSet` and `AuthorEmailSet` as separate events since we they probably don't change together. Also we can imagine to do different things when the email changes like sending a confirmation and such. You should take these considerations into account when moddeling your domain and defining your Events.

Now let's create the necessary code to make the test pass.

In `lib/usernames/events.rb`

```ruby
class UsernamesCreated < Sequent::Event

end

class UsernameAdded < Sequent::Event

end
```

As you can see the events have no attributes yet. This is not necessary to make this test pass. Sequent only looks at the defined attributes and set those as values in the event.  So you need to explicitly declare all attributes.

In `lib/usernames/usernames.rb`

```ruby
class Usernames < Sequent::AggregateRoot
  class UsernameAlreadyRegistered < StandardError; end

  # We can generate and hardcode the UUID since there is only one instance
  ID = "85507d60-8645-4a8a-bdb8-3a9c86a0c635"

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

In `lib/author/events.rb`
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


In `lib/author/commands.rb`
```ruby
class AddAuthor < Sequent::Command
  attrs name: String, email: String
  validates_presence_of :name, :email
end
```

In `lib/author/author.rb`
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

In `lib/author/author_command_handler.rb`
```ruby
class AuthorCommandHandler < Sequent::CommandHandler
  on AddAuthor do |command|
    Usernames.instance.add(command.email)
    repository.add_aggregate(Author.new(command))
  end
end
```

For the next test case we want to assert the following:

```
Given an Author with email 'ben@sequent.io'
When I try to add another author with email 'ben@sequent.io'
Then it should fail
```

This translate to the following rspec test:

```ruby
it 'fails if the username already exists' do
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

`RuntimeError: cannot find aggregate type associated with creation event {UsernamesCreated: @aggregate_id=[85507d60-8645-4a8a-bdb8-3a9c86a0c635], @sequence_number=[1], @created_at=[2018-09-21T14:17:23+02:00]}, did you include an event handler in your aggregate for this event?`

Sequent requires us to define an event handler in the Aggregate for at least the creation event, otherwise Sequent is not able to find an Aggregate in the repository.

So let's change our aggregates to satisfy this demand.

Add to `Usernames`

```ruby
class Usernames < Sequent::AggregateRoot
  ...

  on UsernamesCreated do

  end
end
```

Add to `Author`

```ruby
class Author < Sequent::AggregateRoot
  ...

  on AuthorCreated do

  end
end
```

Running the spec again results in the following error: `expected Usernames::UsernameAlreadyRegistered but nothing was raised`

This is as expected since we didn't implement anything. Let's start by enforcing uniqueness.

Change the `Usernames` aggregate as follows:

```ruby
class Usernames < Sequent::AggregateRoot
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

And the `lib/usernames/events.rb` needs to contain the username attribute to make the test pass.

```ruby
class UsernameAdded < Sequent::Event
  attrs username: String
end
```

The event handlers `UsernamesCreated` and `UsernameAdded` will keep track of the current usernames in a `Set`. Whenever a new name is being added we first check if the name does not yet exist. If not then a new event is applied.

So let's finish up by implementing our last test to ignore case when registering an Author.

The test:

```ruby
it 'ignores case in usernames' do
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

We change our `Usernames` to satisfy this requirement as follows:

```ruby
class Usernames < Sequent::AggregateRoot
  def add(username)
    fail UsernameAlreadyRegistered if @usernames.include?(username.downcase)

    apply UsernameAdded, username: username
  end

  on UsernameAdded do |event|
    @usernames << event.username.downcase
  end
end
```

The last thing we need to do is refactor out `Author` name, and instead use the `Author` `aggregate_id`.

In `spec/lib/post/post_command_handler_spec.rb`:

```ruby
let(:aggregate_id) { Sequent.new_uuid }
let(:author_aggregate_id) { Sequent.new_uuid }

# ...

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

Running the test, it now fails:

```ruby
Sequent::Core::CommandNotValid:
  Invalid command AddPost 3123758b-b847-4451-b524-885c4d04d7b7, errors: {:author=>["can't be blank"]}
```

We need to update the presence validation in `AddPost`. Edit `lib/post/commands.rb`:

```ruby
class AddPost < Sequent::Command
  attrs author_aggregate_id: String, title: String, content: String
  validates_presence_of :author_aggregate_id, :title, :content
end
```

Running the test again reveals a problem in the `Post` aggregate root:

```ruby
Failure/Error: apply PostAuthorChanged, author: command.author

NoMethodError:
  undefined method `author' for #<AddPost:0x00007f8509073ee8>
# ./lib/post/post.rb:5:in `initialize'
```

In `lib/post/post.rb` change

```ruby
class Post < Sequent::AggregateRoot
  def initialize(command)
    super(command.aggregate_id)
    apply PostAdded
    apply PostAuthorChanged, author_aggregate_id: command.author_aggregate_id
    apply PostTitleChanged, title: command.title
    apply PostContentChanged, content: command.content
  end
end
```

And we're back to passing tests. To sum up this guide we have done:

1. Explored the generated `Post` AggregateRoot.
2. Added new functionality to publish a `Post`
3. Added a new Aggregate `Author` and `Usernames` and showed how Aggregate can depend on each other
4. Explored how to add tests in Sequent in order to test the domain

In this guide we mainly focussed on the domain. In the [next guide](/docs/building-a-web-application.html) we will take it a step further and see how can actually build a web application that our Authors can use. We will learn about how to initialize and setup Sequent with Sinatra, learn about [Projectors](/docs/concepts/projector.html) and see how Sequent deals with migrations.
