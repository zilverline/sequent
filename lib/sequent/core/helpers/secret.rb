# frozen_string_literal: true

require 'bcrypt'

module Sequent
  module Core
    module Helpers
      #
      # You can use this in Commands to handle for instance passwords
      # safely. It uses BCrypt to encrypt the Secret.
      #
      # Attributes that are of type Secret are encrypted **after** successful validation in the CommandService
      # automatically. So there is no need to do this yourself, Sequent will take care of this for you.
      # As a result the CommandHandlers will receive the encrypted values.
      #
      # Since this is meant to be used in +Command+s based on input you can
      # put in +String+s and +Secret+s.
      #
      # Example usage:
      #
      #   class CreateUser < Sequent::Command
      #     attrs email: String, password: Sequent::Secret
      #   end
      #
      #   command = CreateUser.new(
      #     aggregate_id: Sequent.new_uuid,
      #     email: 'ben@sequent.io',
      #     password: 'secret',
      #   )
      #
      #   puts command.password
      #   => secret
      #
      #   command.valid?
      #   => true
      #
      #   command = command.parse_attrs_to_correct_types
      #   puts command.password
      #   => SAasdf239as$%^@#%dasfgasasdf (or something similar :-))
      #
      # When command validation fails attributes of type Sequent::Secret are cleared.
      #
      #   command.valid?
      #   => false
      #
      #   puts command.password
      #   => ''
      #
      # There is no real need to use this type in Events since there we are
      # only interested in the encrypted String at that point.
      #
      # Besides the Sequent::Secret type there are also some helper methods available to
      # assist in verifying secrets.
      #
      # See +encrypt_secret+
      # See +re_encrypt_secret+
      # See +verify_secret+
      class Secret
        class << self
          def deserialize_from_json(value)
            new(value)
          end

          ##
          # Creates a hash for the given clear text password.
          #
          def encrypt_secret(clear_text_secret)
            fail ArgumentError, 'clear_text_secret can not be blank' if clear_text_secret.blank?

            BCrypt::Password.create(clear_text_secret)
          end

          ##
          # Creates a hash for the given clear text secret using the given hashed secret as a salt
          # (essentially re-creating the secret hash).
          #
          def re_encrypt_secret(clear_text_secret, hashed_secret)
            fail ArgumentError, 'clear_text_secret can not be blank' if clear_text_secret.blank?
            fail ArgumentError, 'hashed_secret can not be blank' if hashed_secret.blank?

            BCrypt::Engine.hash_secret(clear_text_secret, hashed_secret)
          end

          ##
          # Verifies that the hashed and clear text secret are equal.
          #
          def verify_secret(hashed_secret, clear_text_secret)
            return false if hashed_secret.blank? || clear_text_secret.blank?

            BCrypt::Password.new(hashed_secret) == clear_text_secret
          end
        end

        attr_reader :value

        def initialize(value)
          fail ArgumentError, 'value can not be blank' if value.blank?

          @value = if value.is_a?(Secret)
                     value.value
                   else
                     value
                   end
        end

        def encrypt
          @value = self.class.encrypt_secret(@value)
          self
        end

        def verify_secret(clear_text_secret)
          self.class.verify_secret(@value, clear_text_secret)
        end

        def ==(other)
          return false unless other&.class == Secret

          other.value == @value
        end
      end
    end
  end

  # Shortcut
  Secret = Core::Helpers::Secret
end
