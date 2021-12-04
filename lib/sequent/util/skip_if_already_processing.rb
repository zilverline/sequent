# frozen_string_literal: true

module Sequent
  module Util
    ##
    # Returns if the current Thread is already processing work
    # given the +processing_key+ otherwise
    # it yields the given +&block+.
    #
    # Useful in a Queue and Processing strategy
    def self.skip_if_already_processing(processing_key)
      return if Thread.current[processing_key]

      begin
        Thread.current[processing_key] = true

        yield
      ensure
        Thread.current[processing_key] = nil
      end
    end

    ##
    # Reset the given +processing_key+ for the current Thread.
    #
    # Usefull to make a block protected by +skip_if_already_processing+ reentrant.
    def self.done_processing(processing_key)
      Thread.current[processing_key] = nil
    end
  end
end
