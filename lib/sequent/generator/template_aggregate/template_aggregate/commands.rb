class AddTemplateAggregate < Sequent::Command
  attrs name: String
  validates_presence_of :name
end
