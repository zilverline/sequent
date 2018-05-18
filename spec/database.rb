require 'active_record'

module Database
  def self.test_config
    ActiveSupport::HashWithIndifferentAccess.new({
      adapter: "postgresql",
      host: "localhost",
      username: "sequent",
      password: "",
      database: "sequent_spec_db"
    }).stringify_keys
  end

  def self.establish_connection(config = test_config)
    ActiveRecord::Base.establish_connection(
      config
    )
  end
end
