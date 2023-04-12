---
title: Building a web application with Sequent
---

## Tying it all together

The app we generated in [Getting Started](/docs/getting-started.html) and expanded in [Modelling the Domain](/docs/modelling-the-domain.html) is now ready to be used by real Authors via the Web.
Sequent is not a web framework and can be used with any web framework of your choice. For this guide we use [Sinatra](https://github.com/sinatra/sinatra).

### Installing Sinatra

In your `Gemfile` add:

```ruby
gem 'sinatra'
gem 'sinatra-flash'
gem 'sinatra-contrib'
gem 'webrick'
```

And then run `bundle install`. We will set up Sinatra to run as a [modular application](https://github.com/sinatra/sinatra#serving-a-modular-application).

To make use of Sinatra, we need to create / modify the following files:

Create `./app/web.rb`:

```ruby
require 'sinatra/base'
require 'sinatra/flash' # for displaying flash messages
require 'sinatra/reloader' # for hot reloading changes we make
require_relative '../blog'

class Web < Sinatra::Base
  enable :sessions
  register Sinatra::Flash

  configure :development do
    register Sinatra::Reloader
  end

  get '/' do
    "Welcome to Sequent!"
  end

  helpers ERB::Util
end
```

Update `./config.ru`:

```ruby
require './app/web'

run Web
```

For now this is enough. On the command line execute `bundle exec rackup -p 4567` and open [localhost:4567](http://localhost:4567). If you see `"Welcome to Sequent!"` then we are good to go!

For this guide we want to be able to sign up as an Author. In a later guide we will go full CRUD on the application
and actually create Posts with Authors.

_This guide will not go into styling the web application we are creating, to keep focus on the usage of Sequent in a web application._
{: .notice}

### Sign Up as Author

The `get '/'` method will serve a sign up/sign in form. This form ties to the `AddAuthor` command.

First we change the `get '/'` method to serve us an `erb` containing an html form, allowing us to post a form with the `name` and `email` values that the `AddAuthor` command requires.

In `app/web.rb` add:
```ruby
class Web < Sinatra::Base
  ...

  get '/' do
    erb :index
  end

  ...
end

```

Create `app/views/index.erb`:

```erb
<html>
  <body>
    <pre><%= flash.inspect %></pre>
    <form method="post" action="/authors">
      <div>
        <label for="name">Name</label>
        <input id="name" name="name" type="text"/>
      </div>
      <div>
        <label for="email">Email</label>
        <input id="email" name="email" type="email"/>
      </div>
      <button>Create author</button>
    </form>
  </body>
</html>
```

When visiting [localhost:4567](http://localhost:4567), we see a simple form that allows us to submit values for creating a new Author.

In order to achieve the functionality of actually creating an author, we need to respond to the `post '/authors'` method. We need to parse the post `params` and construct a `Sequent::Command` that we will pass into the [CommandService](concepts/command-service.html).

In `app/web.rb` add:
```ruby
post '/authors' do
  author_id = Sequent.new_uuid
  command = AddAuthor.from_params(params.merge(aggregate_id: author_id))
  Sequent.command_service.execute_commands *command

  flash[:notice] = 'Account created'
  redirect "/"
end
```

<div class="notice--info">
    <p>Calling a command in Sequent generally follows the code signature as seen above:</p>
    <ol>
        <li>Parse parameters to the relevant <code>Command</code></li>
        <li>Execute Command</li>
        <li>Redirect (or do whatever you like)</li>
    </ol>
</div>

Let's fill in a name and an e-mail and see what happens when we click on `Create author`.

It blows up with the following error:
```ruby
ActiveRecord::ConnectionNotEstablished at /
No connection pool with 'primary' found.`
```

Since we are using ActiveRecord outside Rails we need to set up connection handling ourselves.

In order to do so, we can create a simple `Database` class that handles creating connections to the database.

### Connecting to a Database

Create `app/database.rb`:
```ruby
require 'yaml'
require 'erb'
require 'active_record'
require 'sequent'

class Database
  class << self
    def database_config(env = ENV['SEQUENT_ENV'])
      @config ||= YAML.load(ERB.new(File.read('db/database.yml')).result, aliases: true)[env]
    end

    def establish_connection(env = ENV['SEQUENT_ENV'])
      config = database_config(env)
      yield(config) if block_given?
      Sequent::ApplicationRecord.configurations = { env.to_s => config.stringify_keys }
      Sequent::ApplicationRecord.establish_connection config
    end
  end
end
```

As you can see this is just a small wrapper for `ActiveRecord`. To establish the database connections on boot time we add a file `boot.rb`

This will contain all the code needed to require and boot our app. In the case that the SEQUENT_ENV is unset, we set it equal to 'development', which ensures the correct database config is loaded before connecting.

Create `boot.rb`:

```ruby
ENV['SEQUENT_ENV'] ||= 'development'

require './app/database'
Database.establish_connection

require './app/web'
```

Update `config.ru`:

```ruby
require './boot'

run Web
```

Since we are using Sinatra, we also need to give the transaction back to the pool after each request.
So we need to add an `after` block in our `app/web.rb`.

Update `app/web.rb`:
```ruby
class Web < Sinatra::Base
  ...

  after do
    Sequent::ApplicationRecord.clear_active_connections!
  end

  ...
end
```

If you are using the multiple db feature and have more than one role for your database, you need to clear the connection
for each role:
```ruby
class Web < Sinatra::Base
  ...

  after do
    ActiveRecord::Base.connection_handler.all_connection_pools.map(&:role).each do |role|
      ActiveRecord::Base.connection_handler.clear_active_connections!(role)
    end
  end

  ...
end
```

Let's restart the app, fill in a name and email, and submit the form.

`Success!`

Yeah! We successfully transformed an html form to a `Command` and executed it.

When the name and/or e-mail field is empty when submitting the form, you will see a `CommandNotValid` error. This is the error Sequent
raises when `Command` validations fail. You can handle these exceptions any way you like.
{: .notice}

Let's inspect the `sequent_schema` and see if the events are actually stored in the database.

```bash
$ psql blog_development

blog_development=# select aggregate_id, sequence_number, event_type from sequent_schema.event_records order by id, sequence_number;
             aggregate_id             | sequence_number |    event_type
--------------------------------------+-----------------+------------------
 85507d60-8645-4a8a-bdb8-3a9c86a0c635 |               1 | UsernamesCreated
 85507d60-8645-4a8a-bdb8-3a9c86a0c635 |               2 | UsernameAdded
 a8b1a534-f50b-4173-a73b-5b4a8bbcdd12 |               1 | AuthorCreated
 a8b1a534-f50b-4173-a73b-5b4a8bbcdd12 |               2 | AuthorNameSet
 a8b1a534-f50b-4173-a73b-5b4a8bbcdd12 |               3 | AuthorEmailSet
(5 rows)
```

We can see all our events are stored in the event store. The column `event_json` is left out of the query for
readability.

## Creating a Projector and using Migrations

Next we will display the existing authors. In Sequent this is done in 5 steps:

**1. Create the `AuthorRecord`**

Since we are using `ActiveRecord`, we need to create a record class corresponding to `Author` that we will call the `AuthorRecord`.

Create `app/records/author_record.rb`:
```ruby
class AuthorRecord < Sequent::ApplicationRecord
end
```

**2. Create the corresponding SQL file**

Create `db/tables/author_records.sql`:
```sql
CREATE TABLE author_records%SUFFIX% (
    id serial NOT NULL,
    aggregate_id uuid NOT NULL,
    name character varying,
    email character varying,
    CONSTRAINT author_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX author_records_keys%SUFFIX% ON author_records%SUFFIX% USING btree (aggregate_id);
```

**3. Create the [Projector](concepts/projector.html)**

In order to create an `AuthorRecord` based on the events we need to create the `AuthorProjector`

Create `app/projectors/author_projector.rb`:
```ruby
require_relative '../records/author_record'
require_relative '../../lib/author/events'

class AuthorProjector < Sequent::Projector
  manages_tables AuthorRecord

  on AuthorCreated do |event|
    create_record(
      AuthorRecord,
      aggregate_id: event.aggregate_id
    )
  end

  on AuthorNameSet do |event|
    update_all_records(
      AuthorRecord,
      {aggregate_id: event.aggregate_id},
      event.attributes.slice(:name)
    )
  end

  on AuthorEmailSet do |event|
    update_all_records(
      AuthorRecord,
      {aggregate_id: event.aggregate_id},
      event.attributes.slice(:email)
    )
  end
end
```

Remember to ensure it's being required in `blog.rb`:

``` ruby
require_relative 'app/projectors/author_projector'
```

**4. Update Sequent configuration**

Add the new projector to our Sequent config.

Update `config/initializers/sequent.rb`:
```ruby
require './db/migrations'

Sequent.configure do |config|
  config.migrations_class_name = 'Migrations'

  config.command_handlers = [
    PostCommandHandler,
    AuthorCommandHandler,
  ].map(&:new)

  config.event_handlers = [
    PostProjector,
    AuthorProjector
  ].map(&:new)
end
```

**5. Update and run the migration**

Update `db/migrations.rb`:
```ruby
VIEW_SCHEMA_VERSION = 2 # <= update this to version 2

class Migrations < Sequent::Migrations::Projectors
  def self.version
    VIEW_SCHEMA_VERSION
  end

  def self.versions
    {
      '1' => [
        PostProjector
      ],
      '2' => [ # <= add here which projectors you want to rebuild
        AuthorProjector
      ]
    }
  end
end
```

Make sure you have updated your `VIEW_SCHEMA_VERSION` constant.
{: .notice}

Stop your app, run this migration and see what happens:

```bash
$ bundle exec rake sequent:migrate:online && bundle exec rake sequent:migrate:offline
INFO -- : group_exponent: 3
INFO -- : Start replaying events
INFO -- : Number of groups 4096
INFO -- : group_exponent: 1
INFO -- : Start replaying events
INFO -- : Number of groups 16
INFO -- : Migrated to version 2
```

Let's inspect the database again:

```bash
$ psql blog_development
blog_development=# select * from view_schema.author_records;
 id |             aggregate_id             | name |     email
----+--------------------------------------+------+----------------
  1 | a8b1a534-f50b-4173-a73b-5b4a8bbcdd12 | ben  | ben@sequent.io
```

We have authors in the database! This means we can also display them in our app.

## Displaying the Authors

Let's create a new view to display the details of an individual author.

In `app/web.rb` add:

```ruby
class Web < Sinatra::Base``
  ...

  get '/authors/:aggregate_id' do
    @author = AuthorRecord.find_by(aggregate_id: params[:aggregate_id])
    erb :'authors/show'
  end

  ...
end
  
```

Create `app/views/authors/show.erb`:

```erb
<html>
  <body>
    <h1>Author <%= h @author.name %> </h1>
    <p>Email: <%= h @author.email %></p>
    <p>
      <a href="/authors">Show all</a>
    </p>
  </body>
</html>
```

### Navigation within the App

To allow navigation inside the web app we add the following methods and views:

In `app/web.rb` add:

```ruby
class Web < Sinatra::Base
  ...

  get '/authors' do
    @authors = AuthorRecord.all
    erb :'authors/index'
  end

  ...
end
```

In `app/views/index.erb` add:

```erb
  <body>
    <nav style="border-bottom: 1px solid #333; padding-bottom: 1rem;">
      <a href="/authors">All authors</a>
    </nav>

    ...
```


Create `app/views/authors/index.erb`:

```erb
<html>
  <body>
    <p>
      Back to <a href="/">index</a>
    </p>
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Name</th>
          <th>E-mail</th>
        </tr>
      </thead>
      <tbody>
        <% @authors.each do |author| %>
          <tr>
            <td>
              <a href="/authors/<%= author.aggregate_id %>"><%= h author.aggregate_id %></a>
            </td>
            <td><%= h author.name %></td>
            <td><%= h author.email %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </body>
</html>
```

## Summary

In this guide we learned:

1. How to use Sequent in a Sinatra web application
2. Add a Projector and Migration
3. Use the Projector to display data in the web application

The full sourcecode of this guide is available here: [sequent-examples](https://github.com/zilverline/sequent-examples/tree/master/building-a-web-application).

We will continue with this app in the [Finishing the web application](/docs/finishing-the-web-application.html) guide.
