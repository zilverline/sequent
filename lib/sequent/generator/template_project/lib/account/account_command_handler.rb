class AccountCommandHandler < BaseCommandHandler
  on AddAccount do |command|
    repository.add_aggregate Account.new(command)
  end
end
