# frozen_string_literal: true

require 'parser/current'
require 'prism'

class RubyParser
  def self.parse(ruby_code)
    # parser ruby does not support ruby 3.4 or greater and suggests using prism for newer versions
    parser_class = if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.4')
                     Parser::CurrentRuby
                   else
                     Prism::Translation::ParserCurrent
                   end
    parser_class.parse(ruby_code)
  end
end
