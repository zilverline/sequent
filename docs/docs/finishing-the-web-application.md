---
title: Finishing the web application with Sequent
toc: true
toc_sticky: true
classes: []
---

In the previous guide [Building a web application](/docs/building-a-web-application.html)
we created a web application using Sequent with Sinatra. In this guide we will continue
with that web application and will show you how to add Form validation, and let the Author add Posts.

## Adding form validation

Every web application needs some sort of form validation. When creating a Sequent application
you typically bind a [Command](/docs/concepts/command.html) to a web form. A Command represents
user intent, like `AddPost` or `AddAuthor`. Sequent does not provide any view helpers to render
errors in the UI, like for instance Rails does. Sequent does however provide a way to do Command validation
using the Validation module from Rails. See [validations](/docs/concepts/validations.html)
in our Reference Guide for all the details. For this guide we stick to the 'create author' form in our
web application.

In [our blog application](http://localhost:4567), on the home page, clicking the 'Create author'
button without entering any values in the form, will result in the error:

```
Sequent::Core::CommandNotValid at /authors
Invalid command AddAuthor 57424bba-1bb3-4cfb-9d64-5b974ff5f3ff, errors: {:name=>["can't be blank"], :email=>["can't be blank"]}
```
{: .no-copy}

Let's take a look at the `AddAuthor` command:

```ruby
class AddAuthor < Sequent::Command
  attrs name: String, email: String
  validates_presence_of :name, :email
end
```

Currently we only check whether the `name` and `email` attributes are present, but we could add any `validates` method
from the Rails [ActiveModel::Validations](https://api.rubyonrails.org/classes/ActiveModel/Validations.html),
since it is incorporated into Sequent.

In order to provide proper feedback to the user, we need to handle this error in Sinatra and display the error messages
at the correct fields.

### Layout setup

To display the error messages at the correct fields, we need to add Bootstrap for a nifty look and feel and add an erb
layout file to manage all displayed erb code (which gets automatically picked up by Sinatra).

Create the file `app/views/layout.erb` with:
```erb
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css" integrity="sha384-Gn5384xqQ1aoWXA+058RXPxPg6fy4IWvTNh0E263XmFcJlSAwiGgFAW/dAiS6JXm" crossorigin="anonymous">
</head>
<body>
<nav class="navbar navbar-expand navbar-light bg-light">
  <a class="navbar-brand" href="#">Sequent powered Blog</a>
  <ul class="navbar-nav mr-auto">
    <li class="nav-item active">
      <a class="nav-link" href="/">Home</a>
    </li>
    <li class="nav-item">
      <a class="nav-link" href="/authors">Authors</a>
    </li>
  </ul>
</nav>
<main role="main" class="container">
  <% ([flash[:notice]].flatten.compact).each do |info| %>
    <div class="alert alert-info" role="alert">
      <%= h info %>
    </div>
  <% end %>
  <%= yield %>
</main></body></html>
```

### Display error messages
In order to display the error messages in the form we first need to rescue from the `Sequent::Core::CommandNotValid`
in the `post '/authors'` method.

We will make two changes in `app/web.rb`:

1. Add a rescue block and store the errors in `@errors`. We will use this in the erb to display the error messages.
2. Change the `command` attribute into an instance variable `@command`, to allow access from an erb file. This is
   necessary, since we want to be able to get and display any erroneous values (available in the command) the user
   has entered.

Update the `post /authors` action in `app/web.rb` with:
```ruby
  post '/authors' do
  author_id = Sequent.new_uuid
  @command = AddAuthor.from_params(params.merge(aggregate_id: author_id))
  Sequent.command_service.execute_commands @command

  flash[:notice] = 'Account created'
  redirect "/authors/#{author_id}"
rescue Sequent::Core::CommandNotValid => e
  @errors = e.errors
  erb :index
end
```

Next, we need to change the html form and add some helper methods.

Render form fields in red when they contain an invalid value by replacing `app/views/index.erb` to:

```erb
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

Add helpers to get the errors pertaining to certain attributes, add the `helpers` block below `helpers ERB::Util` in `app/web.rb`:

```ruby
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
```

When we now submit an empty form, we can see the input fields are displayed in red:

![author form invalid]({{ site.url }}{{ site.baseurl }}/assets/images/signup_author_form_invalid.png)

The last thing we need to do, is display the error messages underneath the relevant input fields.

To enable this functionality, we replace `app/views/index.erb` with:

```erb
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

When we now submit an empty form, the error messages are displayed underneath the relevant input fields:

![author form invalid with error messages]({{ site.url }}{{ site.baseurl }}/assets/images/signup_author_form_invalid_error_messages.png)

So to summarize, when creating a web application:

1. In Sequent you typically bind forms to `Command` objects
2. You can rescue from the `Sequent::Core::CommandNotValid` in order to display validation errors from the Commands
3. With Sinatra, it is trivial to display those errors the 'Railsy' way.

### Handling Errors outside Command Validation

What about errors that occur outside Command validation? Remember that we enforce uniqueness of email addresses in the 
`Usernames` AggregateRoot. This will raise a `Usernames::UsernameAlreadyRegistered` error and is not rescued in our 
web application.

Again, this is not something that Sequent handles for you, since it is not a web framework. It is however not that hard
to rescue from. Since we only have one custom error class in this example we will rescue this error explicitly.

Change the `post /authors` action in `app/web.rb` to:

```ruby
post '/authors' do
  author_id = Sequent.new_uuid
  @command = AddAuthor.from_params(params.merge(aggregate_id: author_id))
  Sequent.command_service.execute_commands @command

  flash[:notice] = 'Account created'
  redirect "/authors/#{author_id}"
rescue Sequent::Core::CommandNotValid => e
  @errors = e.errors
  erb :index
rescue Usernames::UsernameAlreadyRegistered
  @errors = {email: ['already registered, please choose another']}
  erb :index
end
```

**Tip:** If your application grows, it is possible to create a custom base error class
for your app and rescue from that in your Sinatra controllers.
{: .notice--success}

## Adding and editing Posts

In order to have a fully working blog application, an author needs to be able to submit and edit posts. In this example 
we won't go into detail on how to handle logging in, since that is outside of Sequent scope.

For now we will just add the ability to add and edit a `Post` on the `Author`'s show page. Since this is somewhat of a 
repeat of what we did earlier for creating an Author, we only show the code that needs to be added.

### Domain logic for editing posts

In `lib/post/commands.rb` add:

```ruby
class EditPost < Sequent::Command
  attrs title: String, content: String
  validates_presence_of :title, :content
end
```

In `lib/post/post_command_handler.rb` add:

```ruby
on EditPost do |command|
  do_with_aggregate(command, Post) do |post|
    post.edit(command.title, command.content)
  end
end
```

In `lib/post/post.rb` add:

```ruby
def edit(title, content)
  apply PostTitleChanged, title: title
  apply PostContentChanged, content: content
end
```

Change the handling of `PostAuthorChanged` in `app/projectors/post_projector.rb` to:

```ruby
on PostAuthorChanged do |event|
  update_all_records(PostRecord, {aggregate_id: event.aggregate_id}, event.attributes.slice(:author_aggregate_id))
end
```

### Sinatra actions

In `app/web.rb` add:

```ruby
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
```

### Adding views
Let's add a view for displaying the details of an Author, their posts, and editing/adding a new post.

The complete `app/views/authors/show.erb`

```erb
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

Since we follow a naming convention in the `AddPost` command and `EditPost` command, we can use the same form.

### Update database

In order to access the post records from our author record, we need to add a `has_many` relation to 
`PostRecords` in `AuthorRecord`.

Replace `app/records/author_record.rb` with:

```ruby
class AuthorRecord < Sequent::ApplicationRecord
  has_many :post_records, foreign_key: 'author_aggregate_id', primary_key: 'aggregate_id'
end
```

We also need to add this new `foreign_key` as a new column in the post table.

Replace `db/tables/post_records.sql` with:

```sql
CREATE TABLE post_records%SUFFIX% (
  id serial NOT NULL,
  aggregate_id uuid NOT NULL,
  author_aggregate_id uuid,
  title character varying,
  content character varying,
  CONSTRAINT post_records_pkey%SUFFIX% PRIMARY KEY (id)
);

CREATE UNIQUE INDEX post_records_keys%SUFFIX% ON post_records%SUFFIX% USING btree (aggregate_id);
```

Finally, migrate the database, just like you did before. 

Update the view schema version in `db/migrations.rb` and add the `PostProjector` to the `versions` method:

```ruby
VIEW_SCHEMA_VERSION = 3
```
```ruby
def self.versions
  {
    '1' => [
      PostProjector
    ],
    '2' => [ # Projectors that need to be rebuild:
      AuthorProjector
    ],
    '3' => [
      PostProjector
    ]
  }
end
```

Stop your app and run the migrations:
```bash
bundle exec rake sequent:migrate:online && 
bundle exec rake sequent:migrate:offline
```

```bash
I, [..]  INFO -- : Start migrate_online for version 3
I, [..]  INFO -- : Number of groups 4096
I, [..]  INFO -- : groups: 4096
I, [..]  INFO -- : Start replaying events
I, [..]  INFO -- : Done migrate_online for version 3
I, [..]  INFO -- : Start migrate_offline for version 3
I, [..]  INFO -- : Number of groups 16
I, [..]  INFO -- : groups: 16
I, [..]  INFO -- : Start replaying events
I, [..]  INFO -- : Migrated to version 3
```

### Result

Now you're able to add and edit post for an author.

![author post created]({{ site.url }}{{ site.baseurl }}/assets/images/author_post_created.png)

## Extending Domain Logic

In this guide we have added form validation and added the ability for `Authors` to add and edit `Posts`.
If your domain requires `Authors` to keep track of their `Posts` to enforce a certain business rule, you will
explicitly need to add this to your domain logic. This can be done for instance in the `PostCommandHandler`:

```ruby
on AddPost do |command|
  post = Post.new(command)
  repository.add_aggregate(post)
  author = repository.load_aggregate(command.author_aggregate_id, Author)
  author.add_post(post.id)
end
```

Of course, the requirement of this functionality entirely depends on your domain.


## Summary

In this guide we learned about:

1. Adding the ability for `Authors` to add and edit `Posts`
2. How to add form validation to views using Sequent Command Validation
3. Mapping errors to views using `rescue Sequent::Core::CommandNotValid`

The full source code of the web application is available in the
[sequent-examples repository](https://github.com/zilverline/sequent-examples/tree/master/building-a-web-application).

