require 'active_record'
ActiveRecord::Base.raise_in_transactional_callbacks = true if ActiveRecord::VERSION::STRING >= '4.2'

require 'minitest/autorun'
test_framework = defined?(MiniTest::Test) ? MiniTest::Test : MiniTest::Unit::TestCase

require File.expand_path(File.dirname(__FILE__) + "/../lib/soft_delete")

def connect!
  ActiveRecord::Base.establish_connection :adapter => 'sqlite3', database: ':memory:'
end

def setup!
  connect!
  {
    'parent_model_with_counter_cache_columns' => 'related_models_count INTEGER DEFAULT 0',
    'parent_models' => 'deleted_at DATETIME',
    'soft_deletable_models' => 'parent_model_id INTEGER, deleted_at DATETIME',
    'featureful_models' => 'deleted_at DATETIME, name VARCHAR(32)',
    'plain_models' => 'deleted_at DATETIME',
    'callback_models' => 'deleted_at DATETIME',
    'fail_callback_models' => 'deleted_at DATETIME',
    'related_models' => 'parent_model_id INTEGER, parent_model_with_counter_cache_column_id INTEGER, deleted_at DATETIME',
    'asplode_models' => 'parent_model_id INTEGER, deleted_at DATETIME',
    'employers' => 'name VARCHAR(32), deleted_at DATETIME',
    'employees' => 'deleted_at DATETIME',
    'jobs' => 'employer_id INTEGER NOT NULL, employee_id INTEGER NOT NULL, deleted_at DATETIME',
    'non_soft_deletable_unique_models' => 'name VARCHAR(32), soft_deletable_with_non_soft_deletables_id INTEGER'
  }.each do |table_name, columns_as_sql_string|
    ActiveRecord::Base.connection.execute "CREATE TABLE #{table_name} (id INTEGER NOT NULL PRIMARY KEY, #{columns_as_sql_string})"
  end
end

class WithDifferentConnection < ActiveRecord::Base
  establish_connection adapter: 'sqlite3', database: ':memory:'
  connection.execute 'CREATE TABLE with_different_connections (id INTEGER NOT NULL PRIMARY KEY, deleted_at DATETIME)'
  acts_as_soft_deletable
end

setup!

class SoftDeleteTest < test_framework
  def setup
    ActiveRecord::Base.connection.tables.each do |table|
      ActiveRecord::Base.connection.execute "DELETE FROM #{table}"
    end
  end

  def test_plain_model_class_is_not_soft_deletable
    assert_equal false, PlainModel.soft_deletable?
  end

  def test_soft_delete_model_class_is_soft_deletable
    assert_equal true, SoftDeletableModel.soft_deletable?
  end

  def test_plain_models_are_not_soft_deletable
    assert_equal false, PlainModel.new.soft_deletable?
  end

  def test_soft_deletable_models_are_soft_deletable
    assert_equal true, SoftDeletableModel.new.soft_deletable?
  end

  def test_soft_deletable_models_to_param
    model = SoftDeletableModel.new
    model.save
    to_param = model.to_param

    model.soft_delete

    assert model.to_param
    assert_equal to_param, model.to_param
  end

  # Anti-regression test for #81, which would've introduced a bug to break this test.
  def test_soft_delete_behavior_for_plain_models_callbacks
    model = CallbackModel.new
    model.save
    model.remove_called_variables     # clear called callback flags
    model.soft_delete

    assert_equal nil, model.instance_variable_get(:@update_callback_called)
    assert_equal nil, model.instance_variable_get(:@save_callback_called)
    assert_equal nil, model.instance_variable_get(:@validate_called)
    assert_equal nil, model.instance_variable_get(:@destroy_callback_called)
    assert_equal nil, model.instance_variable_get(:@after_destroy_callback_called)

    assert model.instance_variable_get(:@after_commit_callback_called)
    assert model.instance_variable_get(:@after_soft_delete_callback_called)
  end

  def test_soft_delete_behavior_for_soft_deletable_models
    model = SoftDeletableModel.new
    assert_equal 0, model.class.count
    model.save!
    assert_equal 1, model.class.count
    model.soft_delete

    assert_equal false, model.deleted_at.nil?

    assert_equal 0, model.class.count
    assert_equal 1, model.class.unscoped.count
  end

  def test_update_columns_on_soft_deleted
    record = ParentModel.create
    record.soft_delete

    assert record.update_columns deleted_at: Time.now
  end

  def test_scoping_behavior_for_soft_deletable_models
    parent1 = ParentModel.create
    parent2 = ParentModel.create
    p1 = SoftDeletableModel.create(:parent_model => parent1)
    p2 = SoftDeletableModel.create(:parent_model => parent2)
    p1.soft_delete
    p2.soft_delete
    assert_equal 0, parent1.soft_deletable_models.count
    assert_equal 1, parent1.soft_deletable_models.only_deleted.count
    assert_equal 1, parent1.soft_deletable_models.deleted.count
    p3 = SoftDeletableModel.create(:parent_model => parent1)
    assert_equal 2, parent1.soft_deletable_models.with_deleted.count
    assert_equal [p1,p3], parent1.soft_deletable_models.with_deleted
  end

  def test_soft_delete_behavior_for_featureful_soft_deletable_models
    model = FeaturefulModel.new(:name => "not empty")
    assert_equal 0, model.class.count
    model.save!
    assert_equal 1, model.class.count
    model.soft_delete

    assert_equal false, model.deleted_at.nil?

    assert_equal 0, model.class.count
    assert_equal 1, model.class.unscoped.count
  end

  # Regression test for #24
  def test_chaining_for_soft_deletable_models
    scope = FeaturefulModel.where(:name => "foo").only_deleted
    assert_equal "foo", scope.where_values_hash['name']
    assert_equal 2, scope.where_values.count
  end

  def test_only_destroyed_scope_for_soft_deletable_models
    model = SoftDeletableModel.new
    model.save
    model.soft_delete
    model2 = SoftDeletableModel.new
    model2.save

    assert_equal model, SoftDeletableModel.only_deleted.last
    assert_equal false, SoftDeletableModel.only_deleted.include?(model2)
  end

  def test_default_scope_for_has_many_relationships
    parent = ParentModel.create
    assert_equal 0, parent.related_models.count

    child = parent.related_models.create
    assert_equal 1, parent.related_models.count

    child.soft_delete
    assert_equal false, child.deleted_at.nil?

    assert_equal 0, parent.related_models.count
    assert_equal 1, parent.related_models.unscoped.count
  end

  def test_default_scope_for_has_many_through_relationships
    employer = Employer.create
    employee = Employee.create
    assert_equal 0, employer.jobs.count
    assert_equal 0, employer.employees.count
    assert_equal 0, employee.jobs.count
    assert_equal 0, employee.employers.count

    job = Job.create :employer => employer, :employee => employee
    assert_equal 1, employer.jobs.count
    assert_equal 1, employer.employees.count
    assert_equal 1, employee.jobs.count
    assert_equal 1, employee.employers.count

    employee2 = Employee.create
    job2 = Job.create :employer => employer, :employee => employee2
    employee2.soft_delete
    assert_equal 2, employer.jobs.count
    assert_equal 1, employer.employees.count

    job.soft_delete
    assert_equal 1, employer.jobs.count
    assert_equal 0, employer.employees.count
    assert_equal 0, employee.jobs.count
    assert_equal 0, employee.employers.count
  end

  def test_soft_delete_behavior_for_callbacks
    model = CallbackModel.new
    model.save
    model.soft_delete
    assert model.instance_variable_get(:@after_soft_delete_callback_called)
  end

  def test_soft_delete_on_readonly_record
    model = SoftDeletableModel.create!
    model.readonly!
    assert_raises ActiveRecord::ReadOnlyRecord do
      model.soft_delete
    end
  end

  def test_soft_delete_on_unsaved_record
    model = SoftDeletableModel.new
    model.soft_delete!
    assert model.soft_deleted?
    model.soft_delete!
    assert model.soft_deleted?
  end

  def test_restore
    model = SoftDeletableModel.new
    model.save
    id = model.id
    model.soft_delete

    assert model.soft_deleted?

    model = SoftDeletableModel.only_deleted.find(id)
    model.restore!
    model.reload

    assert_equal false, model.soft_deleted?
  end

  def test_restore_on_object_return_self
    model = SoftDeletableModel.create
    model.soft_delete

    assert_equal model.class, model.restore.class
  end

  # Regression test for #92
  def test_soft_delete_twice
    model = SoftDeletableModel.new
    model.save
    model.soft_delete
    model.soft_delete

    assert_equal 1, SoftDeletableModel.unscoped.where(id: model.id).count
  end

  # Regression test for #92
  def test_soft_delete_bang_twice
    model = SoftDeletableModel.new
    model.save!
    model.soft_delete!
    model.soft_delete!

    assert_equal 1, SoftDeletableModel.unscoped.where(id: model.id).count
  end

  def test_soft_delete_return_value_on_success
    model = SoftDeletableModel.create
    return_value = model.soft_delete

    assert_equal(return_value, model)
  end

  def test_soft_delete_return_value_on_failure
    model = FailCallbackModel.create
    return_value = model.soft_delete

    assert_equal(return_value, false)
  end

  def test_restore_behavior_for_callbacks
    model = CallbackModel.new
    model.save
    id = model.id
    model.soft_delete

    assert model.soft_deleted?

    model = CallbackModel.only_deleted.find(id)
    model.restore!
    model.reload

    assert model.instance_variable_get(:@restore_callback_called)
  end

  def test_multiple_restore
    a = SoftDeletableModel.new
    a.save
    a_id = a.id
    a.soft_delete

    b = SoftDeletableModel.new
    b.save
    b_id = b.id
    b.soft_delete

    c = SoftDeletableModel.new
    c.save
    c_id = c.id
    c.soft_delete

    SoftDeletableModel.restore([a_id, c_id])

    a.reload
    b.reload
    c.reload

    refute a.soft_deleted?
    assert b.soft_deleted?
    refute c.soft_deleted?
  end

  def test_observers_notified
    a = SoftDeletableModelWithObservers.create
    a.soft_delete
    a.restore!

    assert a.observers_notified.select {|args| args == [:before_restore, a]}
    assert a.observers_notified.select {|args| args == [:after_restore, a]}
  end

  def test_observers_not_notified_if_not_supported
    a = SoftDeletableModelWithObservers.create
    a.soft_delete
    a.restore!
    # essentially, we're just ensuring that this doesn't crash
  end

  def test_validates_uniqueness_only_checks_non_deleted_records
    a = Employer.create!(name: "A")
    a.soft_delete
    b = Employer.new(name: "A")
    assert b.valid?
  end

  def test_validates_uniqueness_still_works_on_non_deleted_records
    a = Employer.create!(name: "A")
    b = Employer.new(name: "A")
    refute b.valid?
  end

  def test_soft_delete_fails_if_callback_raises_exception
    parent = AsplodeModel.create

    assert_raises(StandardError) { parent.soft_delete }

    #transaction should be rolled back, so parent NOT deleted
    refute parent.destroyed?, 'Parent record was destroyed, even though AR callback threw exception'
  end

  def test_restore_model_with_different_connection
    ActiveRecord::Base.remove_connection # Disconnect the main connection
    a = WithDifferentConnection.create
    a.soft_delete!
    a.restore!
    # This test passes if no exception is raised
  ensure
    setup! # Reconnect the main connection
  end

  def test_model_without_db_connection
    ActiveRecord::Base.remove_connection

    NoConnectionModel.class_eval{ acts_as_soft_deletable }
  ensure
    setup!
  end

  def test_uniqueness_for_non_soft_delete_associated
    parent_model = SoftDeletableWithNonSoftDeletables.create
    related = parent_model.non_soft_deletable_unique_models.create
    # will raise exception if model is not checked for soft deletability
    related.valid?
  end

end

# Helper classes

class SoftDeletableModel < ActiveRecord::Base
  belongs_to :parent_model
  acts_as_soft_deletable
end

class SoftDeletableWithNonSoftDeletables < ActiveRecord::Base
  self.table_name = 'plain_models'
  has_many :non_soft_deletable_unique_models
end

class NonSoftDeletableUniqueModel < ActiveRecord::Base
  belongs_to :soft_deletable_with_non_soft_deletables
  validates :name, :uniqueness => true
end

class FailCallbackModel < ActiveRecord::Base
  belongs_to :parent_model
  acts_as_soft_deletable

  before_soft_delete { |_| false }
end

class FeaturefulModel < ActiveRecord::Base
  acts_as_soft_deletable
  validates :name, :presence => true, :uniqueness => true
end

class PlainModel < ActiveRecord::Base
end

class CallbackModel < ActiveRecord::Base
  acts_as_soft_deletable
  before_destroy      { |model| model.instance_variable_set :@destroy_callback_called, true }
  before_restore      { |model| model.instance_variable_set :@restore_callback_called, true }
  before_update       { |model| model.instance_variable_set :@update_callback_called, true }
  before_save         { |model| model.instance_variable_set :@save_callback_called, true}
  before_soft_delete  { |model| model.instance_variable_set :@after_soft_delete_callback_called, true }

  after_destroy       { |model| model.instance_variable_set :@after_destroy_callback_called, true }
  after_commit        { |model| model.instance_variable_set :@after_commit_callback_called, true }

  validate            { |model| model.instance_variable_set :@validate_called, true }

  def remove_called_variables
    instance_variables.each {|name| (name.to_s.end_with?('_called')) ? remove_instance_variable(name) : nil}
  end
end

class ParentModel < ActiveRecord::Base
  acts_as_soft_deletable
  has_many :soft_deletable_models
  has_many :related_models
  has_many :very_related_models, :class_name => 'RelatedModel', dependent: :destroy
  has_many :non_soft_deletable_models, dependent: :destroy
  has_one :non_soft_deletable_model, dependent: :destroy
  has_many :asplode_models, dependent: :destroy
  has_one :polymorphic_model, as: :parent, dependent: :destroy
end

class ParentModelWithCounterCacheColumn < ActiveRecord::Base
  has_many :related_models
end

class RelatedModel < ActiveRecord::Base
  acts_as_soft_deletable
  belongs_to :parent_model
  belongs_to :parent_model_with_counter_cache_column, counter_cache: true

  after_soft_delete do |model|
    if parent_model_with_counter_cache_column && parent_model_with_counter_cache_column.reload.related_models_count == 0
      model.instance_variable_set :@after_soft_delete_callback_called, true
    end
  end
end

class Employer < ActiveRecord::Base
  acts_as_soft_deletable
  validates_uniqueness_of :name
  has_many :jobs
  has_many :employees, :through => :jobs
end

class Employee < ActiveRecord::Base
  acts_as_soft_deletable
  has_many :jobs
  has_many :employers, :through => :jobs
end

class Job < ActiveRecord::Base
  acts_as_soft_deletable
  belongs_to :employer
  belongs_to :employee
end

class NonSoftDeletableModel < ActiveRecord::Base
end

class SoftDeletableModelWithObservers < SoftDeletableModel
  def observers_notified
    @observers_notified ||= []
  end

  def self.notify_observer(*args)
    observers_notified << args
  end
end

class AsplodeModel < ActiveRecord::Base
  acts_as_soft_deletable
  before_soft_delete do |r|
    raise StandardError, 'ASPLODE!'
  end
end

class NoConnectionModel < ActiveRecord::Base
end
