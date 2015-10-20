module Sequent
  module Support
    class ViewSchema < ActiveRecord::Schema
      def connection
        BaseViewModel.connection
      end
    end
  end
end
