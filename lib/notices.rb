# This file is for any notices such as deprecation warnings, which should appear
# in the logs during app boot. Adding such warnings in other places causes
# lots of noise with duplicated messages, whereas this file is only
# run once.

warn <<~TEXT

  [DEPRECATION] In future, the location of `sequent_migrations.rb` and
  `sequent_schema.rb` will be determined by 
  `config.database_schema_directory`. 

  Add `config.database_schema_directory = 'config'` (or 
  whatever location you use currently) to set the location in your 
  configuration and avoid future errors.

TEXT
