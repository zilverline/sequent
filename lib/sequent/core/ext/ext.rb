# frozen_string_literal: true

class Symbol
  def self.deserialize_from_json(value)
    value.blank? ? nil : value.try(:to_sym)
  end
end

class String
  def self.deserialize_from_json(value)
    value&.to_s
  end
end

class Integer
  def self.deserialize_from_json(value)
    value.blank? ? nil : value.to_i
  end
end

class Float
  def self.deserialize_from_json(value)
    value.blank? ? nil : value.to_f
  end
end

class BigDecimal
  def self.deserialize_from_json(value)
    return nil if value.nil?

    BigDecimal(value)
  end
end

module Boolean
  def self.deserialize_from_json(value)
    if value.nil?
      nil
    else
      (value.present? ? value : false)
    end
  end
end

class Date
  def self.from_params(value)
    return value if value.is_a?(Date)

    value.blank? ? nil : Date.iso8601(value.dup)
  rescue ArgumentError
    value
  end

  def self.deserialize_from_json(value)
    value.blank? ? nil : Date.iso8601(value.dup)
  end
end

class DateTime
  def self.from_params(value)
    value.blank? ? nil : DateTime.iso8601(value.dup)
  rescue ArgumentError
    value
  end

  def self.deserialize_from_json(value)
    value.blank? ? nil : DateTime.iso8601(value.dup)
  end
end

class Time
  def self.from_params(value)
    value.blank? ? nil : Time.iso8601(value.dup)
  rescue ArgumentError
    value
  end

  def self.deserialize_from_json(value)
    value.blank? ? nil : Time.iso8601(value.dup)
  rescue ArgumentError => e
    return Time.parse(value.dup) if e.message =~ /invalid xmlschema format/ # ruby >= 3
    return Time.parse(value.dup) if e.message =~ /invalid date:/ # ruby 2.7

    raise
  end
end

class Array
  def self.deserialize_from_json(value)
    value
  end
end

class Hash
  def self.deserialize_from_json(value)
    value
  end
end
