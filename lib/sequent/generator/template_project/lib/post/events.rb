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
