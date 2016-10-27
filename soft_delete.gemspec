# -*- encoding: utf-8 -*-
require File.expand_path("../lib/soft_delete/version", __FILE__)

Gem::Specification.new do |s|
  s.name        = "soft_delete"
  s.version     = SoftDelete::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Optimal Workshop"]
  s.email       = []
  s.homepage    = "http://github.com/optimalworkshop/soft_deletion"
  s.summary     = "SoftDelete is a stripped down version of Paranoia which doesn't override destroy on any Active Record objects."
  s.description = "SoftDelete is a stripped down version of Paranoia which doesn't override destroy on any Active Record objects. You would use this plugin / gem if you wished that when you called soft_delete on an Active Record object that it just \"hid\" the record. SoftDelete does this by setting the deleted_at field to the current time when you destroy a record, and hides it by scoping all queries on your model to only include records which do not have a deleted_at field. If you would like to be able to call destroy and have the same behaviour then please use Paranoia."

  s.required_rubygems_version = ">= 1.3.6"

  s.add_dependency "activerecord", "~> 5.0"

  s.add_development_dependency "bundler", ">= 1.0.0"
  s.add_development_dependency "rake"

  s.files        = `git ls-files`.split("\n")
  s.executables  = `git ls-files`.split("\n").map{|f| f =~ /^bin\/(.*)/ ? $1 : nil}.compact
  s.require_path = 'lib'
end
