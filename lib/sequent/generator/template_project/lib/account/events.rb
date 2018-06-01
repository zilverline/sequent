class AccountAdded < Sequent::Event
end

class AccountNameChanged < Sequent::Event
  attrs name: String
end
