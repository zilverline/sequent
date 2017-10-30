module Sequent
  module Util
    def self.skip_if_already_processing(already_processing_key, &block)
      return if Thread.current[already_processing_key]

      begin
        Thread.current[already_processing_key] = true

        block.yield
      ensure
        Thread.current[already_processing_key] = nil
      end
    end
  end
end
