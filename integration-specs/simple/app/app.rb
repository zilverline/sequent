# frozen_string_literal: true

class BaseCommandHandler < Sequent::CommandHandler
  self.abstract_class = true
end

class FirstCommandHandler < BaseCommandHandler
end

class SecondCommandHandler < BaseCommandHandler
end

# Projectors
class BaseProjector < Sequent::Projector
  self.abstract_class = true
end

class FirstProjector < BaseProjector
  manages_no_tables
end

class SecondProjector < Sequent::Projector
  manages_no_tables
end

class ManualProjector < Sequent::Projector
  manages_no_tables

  self.skip_autoregister = true
end

# Workflows
class BaseWorkflow < Sequent::Workflow
  self.abstract_class = true
end

class ManualWorkflow < Sequent::Workflow
  self.skip_autoregister = true
end

class FirstWorkflow < BaseWorkflow
end
