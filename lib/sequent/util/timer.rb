# frozen_string_literal: true

module Sequent
  module Util
    module Timer
      def time(msg)
        start = Time.now
        yield
      ensure
        stop = Time.now
        seconds = stop - start
        Sequent.logger.debug("#{msg} in #{seconds} seconds") if seconds > 1 && Sequent.logger.debug?
      end
    end
  end
end
