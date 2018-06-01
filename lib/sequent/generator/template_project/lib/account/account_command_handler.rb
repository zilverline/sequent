class AccountCommandHandler < Sequent::CommandHandler
  on AddAccount do |command|
    repository.add_aggregate Account.new(command)
  end
end
