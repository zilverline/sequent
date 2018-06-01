class TemplateAggregateAdded < Sequent::Event
end

class TemplateAggregateNameChanged < Sequent::Event
  attrs name: String
end
