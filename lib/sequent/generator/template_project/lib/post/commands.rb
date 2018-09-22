class AddPost < Sequent::Command
  attrs author: String, title: String, content: String
  validates_presence_of :author, :title, :content
end
