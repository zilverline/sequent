---
title: Building a web application with Sequent
toc: true
toc_sticky: true
classes: []
---

The app we generated in [Getting Started](/docs/getting-started.html) and expanded
in [Modelling the Domain](/docs/modelling-the-domain.html) is now ready to be used by real Authors via the Web.
Sequent is not a web framework and can be used with any web framework of your choice. For this guide we
use [Sinatra](https://sinatrarb.com/).

## Installation

In your `Gemfile` add:

```ruby
gem 'sinatra'
gem 'sinatra-flash'
gem 'sinatra-contrib'
gem 'webrick'
gem 'rackup'
```

And then run `bundle install`. We will set up Sinatra to run as
a [modular application](https://github.com/sinatra/sinatra#serving-a-modular-application).

Create `app/web.rb`:

```ruby
require 'sinatra/base'
require 'sinatra/flash' # for displaying flash messages
require 'sinatra/reloader' # for hot reloading changes
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

Create `config.ru`:

```ruby
require './app/web'

run Web
```

For now this is enough. 

To run the application, execute on the command line:
```shell
bundle exec rackup -p 4567
```

Once WEBrick has started without errors, click:

[Open application](http://localhost:4567){: .btn .btn--info .btn--large target="_blank"}

If you see `"Welcome to Sequent!"`, we are good to go!

## Sign up as Author

For this guide we want to be able to sign up as an Author. In a later guide we will go full CRUD on the application
and actually create Posts with Authors.

_To keep focus on the usage of Sequent in a web application, this guide will not go into styling the web application._
{: .notice}

### Form

The `get '/'` method will serve a sign up/sign in form. This form ties to the `AddAuthor` command.

First we change the `get '/'` method to serve us an `erb` containing an html form, allowing us to post a form with
the `name` and `email` values that the `AddAuthor` command requires.

In `app/web.rb` change the `get '/'` to:

```ruby
get '/' do
  erb :index
end
```

Create `app/views/index.erb` with:

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

When opening [our web application](http://localhost:4567), we see a simple form that allows us 
to submit values for creating a new Author.

![signup author form]({{ site.url }}{{ site.baseurl }}/assets/images/signup_author_form.png){: .align-center width="636"}

In order to achieve the functionality of actually creating an author, we need to respond to the `post '/authors'`
method. We need to parse the post `params` and construct a `Sequent::Command` that we will pass into
the [CommandService](concepts/command-service.html).

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

{% capture calling-a-command-signature %}
Calling a command in Sequent generally follows the code signature as seen above:
1. Parse parameters to the relevant `Command`
2. Execute Command
3. Redirect (or do whatever you like)
{% endcapture %}

<div class="notice--info">
  {{ calling-a-command-signature | markdownify }}
</div>

Let's fill in a name and an e-mail and see what happens when we click on `Create author`.

It blows up with the following error:

```text
2024-10-10 15:31:03 - ActiveRecord::ConnectionNotEstablished - No connection pool for 'ActiveRecord::Base' found. (ActiveRecord::ConnectionNotEstablished)
```

Since we are using ActiveRecord outside Rails we need to set up connection handling ourselves.

### Connecting to a Database

We can create a simple `Database` class that handles creating connections to the database.

Create `app/database.rb`:

```ruby
require 'sequent'

class Database
  class << self
    def establish_connection(env = ENV['SEQUENT_ENV'])
      Sequent::Support::Database.connect!(env)
    end
  end
end
```

As you can see this is just a small wrapper for `ActiveRecord`. 

To establish the database connections on boot time we add a file `boot.rb`. This will contain all the code needed to 
require and boot our app. In the case that the `SEQUENT_ENV` is unset, we set it equal to `development`, which ensures 
the correct database config is loaded before connecting.

Create `boot.rb`:

```ruby
ENV['SEQUENT_ENV'] ||= 'development'

require './app/database'
Database.establish_connection

require './app/web'
```

Update `config.ru` to:

```ruby
require './boot'

run Web
```

Since we are using Sinatra, we also need to give the transaction back to the pool after each request.
So we need to add an `after` block in our `app/web.rb`.

Update `app/web.rb` with:

```ruby
after do
  Sequent::ApplicationRecord.connection_handler.clear_active_connections!
end
```

If you are using the multiple db feature and have more than one role for your database, you need to clear the connection
for each role:

```ruby
after do
  Sequent::ApplicationRecord.connection_handler.all_connection_pools.map(&:role).each do |role|
    Sequent::ApplicationRecord.connection_handler.clear_active_connections!(role)
  end
end
```

Restart your web application if it's running.

### Final test

Now try filling in a name and e-mail address [in the application](http://localhost:4567), 
and submit the form.

Success! It works when you see
![signup author created]({{ site.url }}{{ site.baseurl }}/assets/images/signup_author_created.png){: style="margin-top: 1em"}
{: .notice--success}

We successfully transformed an html form to a `Command` and executed it.

When the name and/or e-mail field is empty when submitting the form, you will see a `CommandNotValid` error. This is the
error Sequent raises when `Command` validations fail. You can handle these exceptions any way you like.
{: .notice}

### Inspect the events
Let's inspect the `sequent_schema` and see if the events are actually stored in the database.

1. Run:
```bash
psql blog_development
```
1. Execute the query:
```sql
select aggregate_id, sequence_number, event_type from sequent_schema.event_records order by id, sequence_number;
```
1. This should display:
```text
                aggregate_id             | sequence_number |    event_type
--------------------------------------+-----------------+------------------
 85507d60-8645-4a8a-bdb8-3a9c86a0c635 |               1 | UsernamesCreated
 85507d60-8645-4a8a-bdb8-3a9c86a0c635 |               2 | UsernameAdded
 a8b1a534-f50b-4173-a73b-5b4a8bbcdd12 |               1 | AuthorCreated
 a8b1a534-f50b-4173-a73b-5b4a8bbcdd12 |               2 | AuthorNameSet
 a8b1a534-f50b-4173-a73b-5b4a8bbcdd12 |               3 | AuthorEmailSet
(5 rows)
```
{: .no-copy}

We can see all our events are stored in the event store. The column `event_json` is left out of the query for
readability.

## Store Author records

Next we will project the Author events to records in the database. In Sequent this is done in the following steps.

### Create the `AuthorRecord`

Since we are using `ActiveRecord`, we need to create a record class corresponding to `Author` that we will call
the `AuthorRecord`.

Create `app/records/author_record.rb`:

```ruby
class AuthorRecord < Sequent::ApplicationRecord
end
```

### Create the corresponding SQL file

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

### Create the [Projector](concepts/projector.html)

In order to create an `AuthorRecord` based on the events we need to create the `AuthorProjector`.

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
      { aggregate_id: event.aggregate_id },
      event.attributes.slice(:name)
    )
  end

  on AuthorEmailSet do |event|
    update_all_records(
      AuthorRecord,
      { aggregate_id: event.aggregate_id },
      event.attributes.slice(:email)
    )
  end
end
```

Ensure it's being required in `blog.rb`:

``` ruby
require_relative 'app/projectors/author_projector'
```

### Update and run the migration

To migrate the database, update the view_schema version and add the projectors that need to be rebuild.

Update `db/migrations.rb` to:

```ruby
require 'sequent/migrations/projectors'

VIEW_SCHEMA_VERSION = 2 # <= updated to version 2

class Migrations < Sequent::Migrations::Projectors
  def self.version
    VIEW_SCHEMA_VERSION
  end

  def self.versions
    {
      '1' => [
        PostProjector
      ],
      '2' => [ 
        AuthorProjector # <= Projectors that need to be rebuild
      ]
    }
  end
end
```

Make sure you have updated your `VIEW_SCHEMA_VERSION` constant.
{: .notice}

Stop your app, run the migration and see what happens:
```bash
bundle exec rake sequent:migrate:online && 
bundle exec rake sequent:migrate:offline
```
```bash
I, [..]  INFO -- : Start migrate_online for version 2
I, [..]  INFO -- : Number of groups 4096
I, [..]  INFO -- : groups: 4096
I, [..]  INFO -- : Start replaying events
I, [..]  INFO -- : Done migrate_online for version 2
I, [..]  INFO -- : Start migrate_offline for version 2
I, [..]  INFO -- : Number of groups 16
I, [..]  INFO -- : groups: 16
I, [..]  INFO -- : Start replaying events
I, [..]  INFO -- : Migrated to version 2
```
{: .no-copy}

### Inspect the events

Let's inspect the database again:

```bash
psql blog_development 
```
```sql
select * from view_schema.author_records;
```
```text
 id |             aggregate_id             | name |     email
----+--------------------------------------+------+----------------
  1 | a8b1a534-f50b-4173-a73b-5b4a8bbcdd12 | ben  | ben@sequent.io
```
{: .no-copy}

We have authors in the database! This means we can also display them in our app.

## Displaying the Authors

### Author list

To show a list of authors and allow navigation inside the web app we add the following methods and views.

In `app/web.rb` add:

```ruby
get '/authors' do
  @authors = AuthorRecord.all
  erb :'authors/index'
end
```

In `app/views/index.erb` add this right after the `<body>`:

```erb
<nav style="border-bottom: 1px solid #333; padding-bottom: 1rem;">
  <a href="/authors">All authors</a>
</nav>
```

Create `app/views/authors/index.erb` with:

```erb
<html>
  <body>
    <p>
      Back to <a href="/">index</a>
    </p>
    <table class="table">
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

Restart your web application if it's still running to make sure any changes to `blog.rb` or the Sequent config are 
propagated.

Open [your application](http://localhost:4567), click on 
[All authors](http://localhost:4567/authors) and you should see all author records:

![author list]({{ site.url }}{{ site.baseurl }}/assets/images/author_list.png)

### Author details
Let's create a new view to display the details of an individual author.

In `app/web.rb` add:

```ruby
get '/authors/:author_id' do
  @author = AuthorRecord.find_by(aggregate_id: params[:author_id])
  erb :'authors/show'
end
```

Create `app/views/authors/show.erb` with:

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

In [your application](http://localhost:4567), click on 
[All authors](http://localhost:4567/authors). You should now be able to view the details of an author
by clicking on the ID:

![author details]({{ site.url }}{{ site.baseurl }}/assets/images/author_details.png)


## Summary

In this guide we learned:

1. How to execute a Sequent command in a Sinatra web application
2. Establish a connection to a database
3. Store database records with a Projector and Migration
4. Display the database records

The full source code of the web application is available in the 
[sequent-examples repository](https://github.com/zilverline/sequent-examples/tree/master/building-a-web-application).

We will continue with this web application in the 
[Finishing the web application](finishing-the-web-application.html) guide.
