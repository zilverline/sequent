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
```

And then run `bundle install`. We will setup Sinatra to run as a [modular application](https://github.com/sinatra/sinatra#serving-a-modular-application).

After doing tne necessary plumbing we end up with the following files:

In `./app/web`

```ruby
require 'sinatra/base'
require_relative '../blog'

class Web < Sinatra::Base

  get '/' do
    "Welcome to Sequent!"
  end
end
```

In `./config.ru`

```ruby
require './app/web'
run Web
```

For now this is enough. On the command line execute `rackup -p 4567` and open [localhost:4567](http://localhost:4567). If you see `"Welcome to Sequent!"` then we are good to go!

For this guide we want to be able to signup as Author and create and publish a Post. This guide will not go into styling the web application we are creating in order to keep focus on how to use Sequent in a webapplication.

### Signup as Author

The `/` will serve a signup/signin form. We will start with the signup form. This form ties the `AddAuthor` command. We will be making several changes in our Sinatra app, in order to keep the pace we are going to add the [Sinatra Reloader](http://sinatrarb.com/contrib/reloader) that will hot reload all changes we make.

First we change the `get '/'` to serve us an `erb` with a html form that allows us to post a form with the `name` and `email` that the `AddAuthor` command requires.

The erb `in app/view/index.erb`:

```ruby
<html>
  <body>
    <form method="post" action="/">
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

In `app/web.rb`
```ruby
get '/' do
  erb :index
end
```

When we now open [localhost:4567](http://localhost:4567) we see a simple form that allows us to submit a new Author.

In order to achieve that we need to respond to the `post '/'`. We need to parse the post `params` and construct a `Sequent::Command` that we will pass into the [CommandService](concepts/command-service.html).

In `app/web.rb`
```ruby
post '/' do
  author_id = Sequent.new_uuid
  command = AddAuthor.from_params(params.merge(aggregate_id: author_id))
  Sequent.command_service.execute_commands *command

  flash[:notice] = 'Account created'
  redirect "/author/#{author_id}"
end
```

Every post of a command that you do in Sequent basically has this signature.

Let's see what happens if we hit `Create author`.

It blows up with

```ruby
ActiveRecord::ConnectionNotEstablished at /
No connection pool with 'primary' found.`
```

Since we are using ActiveRecord outside Rails we need to setup connection handling ourselves.

# WORK IN PROGRESS
