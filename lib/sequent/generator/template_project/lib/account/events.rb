class Account
  class AccountAdded < Sequent::Core::Event
  end

  class AccountNameChanged < Sequent::Core::Event
    attrs name: String
  end
end
