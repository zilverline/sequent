# frozen_string_literal: true

require 'active_record'
require_relative 'sequent_oj'
require_relative '../application_record'

module Sequent
  module Core
    class EventType < Sequent::ApplicationRecord
      self.inheritance_column = nil
    end
  end
end
