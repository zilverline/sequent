# frozen_string_literal: true

require 'bundler/setup'
Bundler.setup

ENV['SEQUENT_ENV'] ||= 'test'

require_relative '../simple'
