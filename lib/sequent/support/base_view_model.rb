module Sequent
  module Support
    # Base view model to manage the view connection pool
    class BaseViewModel < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
