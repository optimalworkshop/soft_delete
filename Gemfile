source 'https://rubygems.org'

gem 'sqlite3', :platforms => [:ruby]
gem 'activerecord-jdbcsqlite3-adapter', :platforms => [:jruby]

platforms :rbx do
  gem 'rubysl', '~> 2.0'
  gem 'rubysl-test-unit'
  gem 'rubinius-developer_tools'
end

<<<<<<< Updated upstream
rails = ENV['RAILS'] || '~> 3.2'
=======
rails = ENV['RAILS'] || '~> 3.2.0'
>>>>>>> Stashed changes

gem 'rails', rails

# Specify your gem's dependencies in paranoia.gemspec
gemspec
