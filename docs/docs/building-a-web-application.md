---
title: Building a web application with Sequent
---

## Tying it all together

The app we generated in [Getting Started](/docs/getting-started.html) and expanded in [Modelling the Domain](/docs/modelling-the-domain.html) is now ready to be used by real Authors via the Web.
Sequent is no webframework and can be used with any webframework you want. For this guide we choose [Sinatra](https://github.com/sinatra/sinatra).

### Installing Sinatra

Add to your `Gemfile`:

```ruby
gem 'sinatra'
gem 'sinatra-flash'
gem 'sinatra-contrib'
```

And then run `bundle install`. We will setup Sinatra to run as a [modular application](https://github.com/sinatra/sinatra#serving-a-modular-application).

After doing tne necessary plumbing we end up with the following files:

In `./app/web`

```ruby
require 'sinatra/base'
require 'sinatra/flash' # for displaying flash messages
require 'sinatra/reloader' # for hot reloading changes we make
require_relative '../blog'

class Web < Sinatra::Base
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

In `./config.ru`

```ruby
require './app/web'
run Web
```

For now this is enough. On the command line execute `rackup -p 4567` and open [localhost:4567](http://localhost:4567). If you see `"Welcome to Sequent!"` then we are good to go!

For this guide we want to be able to signup as Author. In a later guide we will go full CRUD on the application
and actually create Posts with Authors.

_This guide will not go into styling the web application we are creating in order to keep focus on how to use Sequent in a webapplication._
{: .notice}

### Signup as Author

The `get '/'` will serve a signup/signin form. This form ties the `AddAuthor` command.

First we change the `get '/'` to serve us an `erb` with a html form that allows us to post a form with the `name` and `email` that the `AddAuthor` command requires.

The erb `in app/views/index.erb`:

```ruby
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

And change the `get '/'` as follows:

In `app/web.rb`:
```ruby
get '/' do
  erb :index
end
```

When we now open [localhost:4567](http://localhost:4567) we see a simple form that allows us to submit a new Author.

In order to achieve that we need to respond to the `post '/authors'`. We need to parse the post `params` and construct a `Sequent::Command` that we will pass into the [CommandService](concepts/command-service.html).

In `app/web.rb`:
```ruby
post '/authors' do
  author_id = Sequent.new_uuid
  command = AddAuthor.from_params(params.merge(aggregate_id: author_id))
  Sequent.command_service.execute_commands *command

  flash[:notice] = 'Account created'
  redirect "/"
end
```

Every `post` of a Command that in Sequent basically has the above code signature:

1. Parse parameters to `Command`
2. Execute Command
3. Redirect (or do whatever you like)

Let's fill in a name and an e-mail and see what happens if we hit `Create author`.

It blows up with the following error:
```ruby
ActiveRecord::ConnectionNotEstablished at /
No connection pool with 'primary' found.`
```

Since we are using ActiveRecord outside Rails we need to setup connection handling ourselves.

In order to do so we can create simple `Database` class that handles creating connections to the database.

In `app/database.rb`:
```ruby
require 'yaml'
require 'erb'
require 'active_record'

class Database
  class << self
    def database_config(env = ENV['RACK_ENV'])
      @config ||= YAML.load(ERB.new(File.read('db/database.yml')).result)[env]
    end

    def establish_connection(env = ENV['RACK_ENV'])
      config = database_config(env)
      yield(config) if block_given?
      Sequent::ApplicationRecord.configurations[env.to_s] = config.stringify_keys
      Sequent::ApplicationRecord.establish_connection config
    end
  end
end
```

As you can see this is just a small wrapper for `ActiveRecord`. To establish the database connections on boot time we add a file `boot.rb`

This will contain all the code needed to require and boot our app.

```ruby
require './app/database'
Database.establish_connection

require './app/web'
```

The `config.ru` now looks like this:

```ruby
require './boot'

run Web
```

And since we are using Sinatra we also need to give the transaction back to the pool after each request.
So we need to add an `after` block in our `app/web.rb`:
```ruby
class Web < Sinatra::Base
  ...

  after do
    Sequent::ApplicationRecord.clear_active_connections!
  end

  ...
end
```

After we restart the app and fill in a name and email let's see what happens.

`Success!`

Yeah! We succesfully transformed a html form to a `Command` and executed it.


When you forget to fill in name and or e-mail you will see a `CommandNotValid` error. This is the error Sequent
raises when `Command` validations fail. You can handle these exceptions any way you like.
{: .notice}

Let's inspect the `sequence_schema` and see if the events are actually stored in the database.

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

Next step is to display the existing authors. In Sequent this is done in 4 steps:

**1. Create the `AuthorRecord`.**

Since we are using `ActiveRecord` we need to create the `AuthorRecord`

`app/records/author_record.rb`
```ruby
class AuthorRecord < Sequent::ApplicationRecord
end
```

**2. Create the corresponding sql file**

`db/tables/author_records.sql`
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

In order to create and `AuthorRecord` based on the events we need to create the `AuthorProjector`

`app/projectors/author_projector.rb`
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

And don't forget to ensure it's being required.

`blog.rb`
``` ruby
require_relative 'app/projectors/author_projector'
```

**4. Update Sequent configuration**
Then we can add this projector to our Sequent config `config/initializers/sequent.rb`

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

**5. Create and run the migration**

In `db/migrations.rb`
```ruby
VIEW_SCHEMA_VERSION = 2 # <= update this to version 2

class Migrations < Sequent::Migrations::Projectors
  ...

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

Stop your app and now run this migration and see what happens:

```bash
(master)$ bundle exec rake sequent:migrate:online && bundle exec rake sequent:migrate:offline
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
(master)$ psql blog_development
blog_development=# select * from view_schema.author_records;
 id |             aggregate_id             | name |     email
----+--------------------------------------+------+----------------
  1 | a8b1a534-f50b-4173-a73b-5b4a8bbcdd12 | ben  | ben@sequent.io
```

We have authors in the database! This means we can also display them in our app:

Change the `app/web.rb`

```ruby
  get '/authors/id/:aggregate_id' do
    @author = AuthorRecord.find_by(aggregate_id: params[:aggregate_id])
    erb :'authors/show'
  end
```

Add the `app/views/authors/show.erb`

```ruby
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

To create a navigatable web app we also add the following code:

In `app/web.rb`

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

In `app/views/authors/index.erb`

```ruby
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
              <a href="/authors/id/<%= author.aggregate_id %>"><%= h author.aggregate_id %></a>
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

So that's it for this guide. In this guide we learned:

1. How to use Sequent in a Sinatra web application
2. Add a Projector and Migration
3. Use the Projector to display data in the web application

The full sourcecode of this guide is available here: [sequent-examples](https://github.com/zilverline/sequent-examples/tree/master/building-a-web-application)

We will continue with this app in the [Finishing the web application](/docs/finishing-the-web-application.html) guide.
