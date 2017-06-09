source 'https://rubygems.org'

gem 'sqlite3', :platforms => [:ruby]

platforms :rbx do
  gem 'rubysl', '~> 2.0'
  gem 'rubysl-test-unit'
  gem 'rubinius-developer_tools'
end

rails = ENV['RAILS'] || '~> 5.0.0'

gem 'rails', rails

# Specify your gem's dependencies in soft_delete.gemspec
gemspec
