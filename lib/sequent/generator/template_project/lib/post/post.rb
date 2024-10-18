# frozen_string_literal: true

class Post < Sequent::AggregateRoot
  def initialize(command)
    super(command.aggregate_id)
    apply PostAdded
    apply PostAuthorChanged, author: command.author
    apply PostTitleChanged, title: command.title
    apply PostContentChanged, content: command.content
  end

  on PostAdded do
  end

  on PostAuthorChanged do |event|
    @author = event.author
  end

  on PostTitleChanged do |event|
    @title = event.title
  end

  on PostContentChanged do |event|
    @content = event.content
  end
end
