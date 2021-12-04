# frozen_string_literal: true

module Sequent
  module Util
    module Printer
      def recursively_print(e)
        logger.error "#{e}\n\n#{e.backtrace.join("\n")}"

        while e.cause
          logger.error '+++++++++++++++ CAUSE +++++++++++++++'
          logger.error "#{e.cause}\n\n#{e.cause.backtrace.join("\n")}"
          e = e.cause
        end
      end
    end
  end
end
