require 'active_record'

module Sequent
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
