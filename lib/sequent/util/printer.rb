module Sequent
  module Util
    module Printer
      def recursively_print(e)
        logger.error "#{e.to_s}\n\n#{e.backtrace.join("\n")}"

        while e.cause do
          logger.error "+++++++++++++++ CAUSE +++++++++++++++"
          logger.error "#{e.cause.to_s}\n\n#{e.cause.backtrace.join("\n")}"
          e = e.cause
        end
      end
    end
  end
end

