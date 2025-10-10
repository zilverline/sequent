# frozen_string_literal: true

ActiveRecord::Base.configurations = YAML.load_file('db/database.yml', aliases: true)
ActiveRecord::Tasks::DatabaseTasks.env = Sequent.env
ActiveRecord::Tasks::DatabaseTasks.db_dir = 'db'
