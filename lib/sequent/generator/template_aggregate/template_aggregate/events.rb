class TemplateAggregateAdded < Sequent::Core::Event
end

class TemplateAggregateNameChanged < Sequent::Core::Event
  attrs name: String
end
