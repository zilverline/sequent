class Symbol

  def self.parse_from_string(value)
    deserialize_from_json value
  end

  def self.deserialize_from_json(value)
    value.blank? ? nil : value.try(:to_sym)
  end

end

class String
  def self.parse_from_string(value)
    value
  end

  def self.deserialize_from_json(value)
    value
  end

end

class Integer
  def self.add_validations_for(klass, field)
    klass.validates_numericality_of field, only_integer: true, allow_nil: true, allow_blank: true
  end

  def self.parse_from_string(value)
    Integer(value) unless value.blank?
    deserialize_from_json value
  end

  def self.deserialize_from_json(value)
    value.blank? ? nil : value.to_i
  end

end

class Boolean
  def self.parse_from_string(value)
    if value.blank? && !(value.is_a?(TrueClass) || value.is_a?(FalseClass))
      nil
    else
      (value.is_a?(TrueClass) || value == "true")
    end
  end

  def self.deserialize_from_json(value)
    value.nil? ? nil : (value.present? ? value : false)
  end

end

class Date
  def self.add_validations_for(klass, field)
    klass.validates field, "sequent::Core::Helpers::Date" => true
  end

  def self.parse_from_string(value)
    return if value.blank?
    value.is_a?(Date) ? value : Date.strptime(value, "%d-%m-%Y")
  end

  def self.deserialize_from_json(value)
    value.blank? ? nil : Date.iso8601(value.dup)
  end

end

class DateTime
  def self.add_validations_for(klass, field)
    klass.validates field, "sequent::Core::Helpers::DateTime" => true
  end

  def self.parse_from_string(value)
    value.is_a?(DateTime) ? value : deserialize_from_json(value)
  end

  def self.deserialize_from_json(value)
    value.blank? ? nil : DateTime.iso8601(value.dup)
  end

end

class Array

  def self.deserialize_from_json(value)
    value
  end
end
