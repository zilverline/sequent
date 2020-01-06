---
title: Finishing the web application with Sequent
---

In the previous guide [Building a web application](/docs/building-a-web-application.html)
we created a web application using Sequent with Sinatra. In this guide we will continue
with that web application and will show you how to add Form validation, and let the Author add Posts.

### Adding form validation

Every web application needs some sort of form validation. When creating a Sequent application
you typically bind a [Command](/docs/concepts/command.html) to a web form. A Command respresents
user intent, like `AddPost` or `AddAuthor`. Sequent does not provide any view helpers to render
errors in the UI like for instance Rails does. Sequent does provide a way to do Command validation
using the Validation module from Rails. Please check [validations](/docs/concepts/validations.html)
in our Reference Guide for all the details. For now we stick to the 'create author' form in our
web application.

If we fire up the blog application and open the [home page](http://localhost:4567) and
directly hit the 'Create author' button the form blows up with a

```ruby
Sequent::Core::CommandNotValid at /authors
Invalid command AddAuthor 57424bba-1bb3-4cfb-9d64-5b974ff5f3ff, errors: {:name=>["can't be blank"], :email=>["can't be blank"]}
```

Let's refresh our minds and see what `AddAuthor` looks like:

```ruby
class AddAuthor < Sequent::Command
  attrs name: String, email: String
  validates_presence_of :name, :email
end
```

The only checks we do it that the `name` and `email` should be present, but
since Sequent uses the Rails validation module you can add any `validates` method
available.

So in order to provide proper feedback to the user we need to handle this
error in Sinatra and display the error messages at the correct fields.

For this guide we somewhat refactored the web application and added bootstrap
for some nifty look and feel and extracted some command erb code into
a default layout, this is automatically picked up by Sinatra.

In `app/view/layout.erb`
```ruby
<html>
  <head>
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css" integrity="sha384-Gn5384xqQ1aoWXA+058RXPxPg6fy4IWvTNh0E263XmFcJlSAwiGgFAW/dAiS6JXm" crossorigin="anonymous">
  </head>
  <body>
    <div class="container">
      <h1 style="margin-bottom: 20px">Sequent powered Blog</h1>
      <%= yield %>
    </div>
  </body>
</html>
```

In order to display the error messages in the form we first need to
rescue from the `Sequent::Core::CommandNotValid` in the `post '/authors'`

In `app/web.rb`

```ruby
  post '/authors' do
    author_id = Sequent.new_uuid
    @command = AddAuthor.from_params(params.merge(aggregate_id: author_id))
    Sequent.command_service.execute_commands @command

    flash[:notice] = 'Account created'
    redirect "/authors/id/#{author_id}"
  rescue Sequent::Core::CommandNotValid => e
    @errors = e.errors
    erb :index
  end
```

We have changed 2 things here:

1. Added the rescue block and stored the errors in `@errors`. We will
use this in the erb to display the error messages.
2. We have changed the `command` attribute into an instance variable `@command`
so it is available in the erb for displaying the value in the form fields.
This is necessary when submitting the form with an error. If this happens
you want to show the values the user typed in.

Now we need to change the html form. First we add some code to ensure the
form fields are rendered in red when it contains an invalid value:

In `app/views/index.erb`

```ruby
<form method="post" action="/authors">
  <div class="form-group">
    <label for="name">Name</label>
    <input
      id="name"
      name="name"
      type="text"
      value="<%= h @command&.name %>"
      class="form-control <%= error_css_class(:name) %>"
    />
  <div class="form-group">
    <label for="email">Email</label>
    <input
      id="email"
      name="email"
      type="email"
      value="<%= h @command&.email %>"
      class="form-control <%= error_css_class(:email) %>"
    />
  </div>
  <button class="btn btn-primary">Create author</button>
</form>
```

And we have added the following helpers to get the errors for certain
attributes

In `app/web.rb`

```ruby
class Web < Sinatra::Base
  # omitted ...

  helpers do
    def has_errors_for(attribute)
      @errors && @errors[attribute].present?
    end

    def errors(attribute)
      @errors[attribute] if has_errors_for(attribute)
    end

    def error_css_class(attribute)
      has_errors_for(attribute) ? 'is-invalid' : ''
    end
  end
end
```

When we now submit an empty form we can see the input fields are
displayed in red. The last thing we need to do is display the error
messages underneath the input fields.

We end up with this:

In `app/views/index.erb`

```ruby
<form method="post" action="/authors">
  <div class="form-group">
    <label for="name">Name</label>
    <input
      id="name"
      name="name"
      type="text"
      value="<%= h @command&.name %>"
      class="form-control <%= error_css_class(:name) %>"
    />
    <% if has_errors_for(:name) %>
      <div class="invalid-feedback">
        <% errors(:name).each do |error| %>
          <p><%= h error %></p>
        <% end %>
      </div>
    <% end %>
  <div class="form-group">
    <label for="email">Email</label>
    <input
      id="email"
      name="email"
      type="email"
      value="<%= h @command&.email %>"
      class="form-control <%= error_css_class(:email) %>"
    />
    <% if has_errors_for(:email) %>
      <div class="invalid-feedback">
        <% errors(:email).each do |error| %>
          <p><%= h error %></p>
        <% end %>
      </div>
    <% end %>
  </div>
  <button class="btn btn-primary">Create author</button>
</form>
```

When we now submit an empty form the error messages are displayed
underneath the input fields.

So to summarize, when creating a web application:

1. In Sequent you typically bind forms to `Command` objects
2. You can rescue from the `Sequent::Core::CommandNotValid` in order
to display validation errors in the Commands
3. Using Sinatra it is trivial to display those errors the 'Railsy' way.

What about errors that occur outside Command validation? Remember that
we enforce uniqueness of email addresses in the `Usernames` AggregateRoot.
This will raise a `Usernames::UsernameAlreadyRegistered` error and is
not rescued in our web application.

Again this is not something that Sequent handles for you since it is not
a web framework. It is however not that hard to rescue from. Since we only
have one custom error class in this example we will rescue this error explictly.

**Tip:** If your application grows you can of course create a base error class
for your app and rescue from that in you Sinatra controllers.
{: .notice--success}

In `app/web.rb`

```ruby
class Web < Sinatra::Base
  post '/authors' do
    author_id = Sequent.new_uuid
    @command = AddAuthor.from_params(params.merge(aggregate_id: author_id))
    Sequent.command_service.execute_commands @command

    flash[:notice] = 'Account created'
    redirect "/authors/id/#{author_id}"
  rescue Sequent::Core::CommandNotValid => e
    @errors = e.errors
    erb :index
  rescue Usernames::UsernameAlreadyRegistered
    @errors = {email: ['already registered, please choose another']}
    erb :index
  end
end
```

### Adding and editing Posts

In order to have a fully working blog application an author needs
to be able to submit and edit posts. In this example we won't go into detail
on how to do login, since that is not in Sequent scope.

For now we will just add the ability to add and edit a `Post` on the `Author`s show page.

To be able to add and edit posts we need to add the following code. Since this
is somewhat of a repeat of what we did earlier in creating an Author we just
show the code that needs to be added.

First add the domain logic for editting posts.

In `lib/post/commands.rb`

```ruby
class EditPost < Sequent::Command
  attrs title: String, content: String
  validates_presence_of :title, :content
end
```

In `lib/post/post_command_handler.rb`

```ruby
class PostCommandHandler < Sequent::CommandHandler
  on EditPost do |command|
    do_with_aggregate(command, Post) do |post|
      post.edit(command.title, command.content)
    end
  end
end
```

In `lib/post/post.rb`

```ruby
class Post < Sequent::AggregateRoot
  def edit(title, content)
    apply PostTitleChanged, title: title
    apply PostContentChanged, content: content
  end
end
```

And the final version of the `PostProjector` is

In `app/projectors/post_projector.rb`

```ruby
require_relative '../records/post_record'
require_relative '../../lib/post/events'

class PostProjector < Sequent::Projector
  manages_tables PostRecord

  on PostAdded do |event|
    create_record(PostRecord, aggregate_id: event.aggregate_id)
  end

  on PostAuthorChanged do |event|
    update_all_records(
      PostRecord,
      {aggregate_id: event.aggregate_id},
      event.attributes.slice(:author_aggregate_id)
    )
  end

  on PostTitleChanged do |event|
    update_all_records(PostRecord, {aggregate_id: event.aggregate_id}, event.attributes.slice(:title))
  end

  on PostContentChanged do |event|
    update_all_records(PostRecord, {aggregate_id: event.aggregate_id}, event.attributes.slice(:content))
  end
end

```

In `app/web.rb`

```ruby
class Web < Sinatra::Base
  post '/authors/id/:author_id/post' do
      post_id = Sequent.new_uuid
  
      @command = AddPost.from_params(
        params.merge(
          aggregate_id: post_id,
          author_aggregate_id: params[:author_id],
        )
      )
      Sequent.command_service.execute_commands @command
  
      flash[:notice] = 'Post created'
  
      redirect "/authors/id/#{params[:author_id]}/post/#{post_id}"
    rescue Sequent::Core::CommandNotValid => e
      @author = AuthorRecord.find_by(aggregate_id: params[:author_id])
      @errors = e.errors
      erb :'authors/show'
    end

  get '/authors/id/:author_id/post/:post_id' do
    @author = AuthorRecord.find_by(aggregate_id: params[:author_id])
    post_record = PostRecord.find_by(aggregate_id: params[:post_id])
    @command = EditPost.new(
      aggregate_id: params[:post_id],
      title: post_record.title,
      content: post_record.content,
    )
    erb :'authors/show'
  end

  post '/authors/id/:author_id/post/:post_id' do
    @command = EditPost.from_params(
      params.merge(
        aggregate_id: params[:post_id],
      )
    )

    Sequent.command_service.execute_commands @command
    flash[:notice] = 'Post saved'
    redirect back
  rescue Sequent::Core::CommandNotValid => e
    @author = AuthorRecord.find_by(aggregate_id: params[:author_id])
    @errors = e.errors
    erb :'authors/show'
  end

  helpers do
    def post_action(command)
      @command&.is_a?(EditPost) ? "/authors/id/#{params[:author_id]}/post/#{command.aggregate_id}" : "/authors/id/#{params[:author_id]}/post"
    end
  end
end
```

We also need to add the form for submitting posts in the Author show

The complete `app/views/authors/show.erb`

```ruby
<div class="container">
  <p>
    <a href="/authors">Back to all authors</a>
  </p>
  <h1>Author <%= h @author.name %> </h1>

  <table class="table">
    <tbody>
      <% @author.post_records.order(:id).each do |post_record| %>
        <tr>
          <td><%= h post_record.title %></td>
          <td>
            <a href="<%= "/authors/id/#{@author.aggregate_id}/post/#{post_record.aggregate_id}" %>">
              <%= h post_record.aggregate_id %>
            </a>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>

  <p>Email: <%= h @author.email %></p>

  <form method="post" action="<%= post_action(@command) %>">
    <div class="form-group">
      <label for="title">Title</label>
      <input
        id="title"
        name="title"
        type="text"
        value="<%= h @command&.title %>"
        class="form-control <%= error_css_class(:title) %>"
        />
      <% if has_errors_for(:title) %>
        <div class="invalid-feedback">
          <% errors(:title).each do |error| %>
            <p><%= h error %></p>
          <% end %>
        </div>
      <% end %>
    </div>
    <div class="form-group">
      <label for="content">Content</label>
      <textarea
        id="content"
        name="content"
        rows="10"
        class="form-control <%= error_css_class(:content) %>"
      ><%= h @command&.content %></textarea>
      <% if has_errors_for(:content) %>
        <div class="invalid-feedback">
          <% errors(:content).each do |error| %>
            <p><%= h error %></p>
          <% end %>
        </div>
      <% end %>
    </div>

    <button class="btn btn-primary">Save</button>
  </form>
</div>
```

Since we follow a naming convention in the `AddPost` command and `EditPost` command
we can use the same form.

As we want to access the post records from our author record we need to add an has_many relation in `app/records/author_record.rb`

```ruby
  class AuthorRecord < Sequent::ApplicationRecord
    has_many :post_records, foreign_key: 'author_aggregate_id', primary_key: 'aggregate_id'
  end
```

We need to add this new foreign_key as a new column in the post table. We need to update `db/tables/post_records.sql`
                                                                                                                                                
```ruby
 CREATE TABLE post_records%SUFFIX% (
     id serial NOT NULL,
     aggregate_id uuid NOT NULL,
     author_aggregate_id uuid,
     author character varying,
     title character varying,
     content character varying,
     CONSTRAINT post_records_pkey%SUFFIX% PRIMARY KEY (id)
 );
 
 CREATE UNIQUE INDEX post_records_keys%SUFFIX% ON post_records%SUFFIX% USING btree (aggregate_id);
```
Then run & update the migration as you did in 3.Building a web application > 5. Update and run the migration


### Wrap up

In this guide we have added form validation and added the possibility
for `Author`s to add and edit `Post`s.
If in your domain it is also necessary for an `Author`
keeps track of it's posts to enforce some sort of business rule
then you will also need to add this to your domain logic.
This can be done for instance in the `PostCommandHandler`:

```ruby
  on AddPost do |command|
    post = Post.new(command)
    repository.add_aggregate(post)
    author = repository.load_aggregate(command.author_aggregate_id, Author)
    author.add_post(post.id)
  end
```

Of course this entirely depends on your domain whether it is important to you.
