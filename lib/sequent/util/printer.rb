# frozen_string_literal: true

module Sequent
  module Util
    module Printer
      def recursively_print(e)
        logger.error "#{e.class.name}: #{e.message}\n\n#{e.backtrace.join("\n")}"

        if e.cause
          logger.error '+++++++++++++++ CAUSE +++++++++++++++'
          recursively_print(e.cause)
        end
      end
    end
  end
end
