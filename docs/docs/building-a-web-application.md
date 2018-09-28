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

For this guide we want to be able to signup as Author and create and publish a Post.

### Signup as Author

The `/` will serve a signup/signin form. We will start with the signup form. This form ties the `AddAuthor` command.

# WORK IN PROGRESS

LAST COMMITTED 28-09-2018...

