require 'active_record'

module Database
  def self.establish_connection
    ActiveRecord::Base.establish_connection(
      :adapter  => "postgresql",
      :host     => "localhost",
      :username => "sequent",
      :password => "",
      :database => "sequent_spec_db"
    )
  end
end
