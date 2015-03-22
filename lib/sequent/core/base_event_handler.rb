require_relative 'helpers/self_applier'

module Sequent
  module Core
    class BaseEventHandler
      extend Forwardable
      include Helpers::SelfApplier

      def initialize(record_session = Sequent::Core::RecordSessions::ActiveRecordSession.new)
        @record_session = record_session
      end

      def_delegators :@record_session, :update_record, :create_record, :create_or_update_record, :get_record!, :get_record,
                     :delete_all_records, :update_all_records, :do_with_records, :do_with_record, :delete_record,
                     :find_records, :last_record

    end
  end
end
