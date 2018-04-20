class Account
  class AddAccount < Sequent::Core::Command
    attrs name: String
    validates_presence_of :name
  end
end
