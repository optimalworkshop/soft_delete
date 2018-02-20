require 'active_record'
require 'minitest/autorun'
require 'soft_delete'

test_framework = defined?(MiniTest::Test) ? MiniTest::Test : MiniTest::Unit::TestCase

if ActiveRecord::Base.respond_to?(:raise_in_transactional_callbacks=)
  ActiveRecord::Base.raise_in_transactional_callbacks = true
end

def connect!
  ActiveRecord::Base.establish_connection :adapter => 'sqlite3', database: ':memory:'
end

def setup!
  connect!
  {
    'parent_model_with_counter_cache_columns' => 'related_models_count INTEGER DEFAULT 0',
    'parent_models' => 'deleted_at DATETIME',
    'soft_deletable_models' => 'parent_model_id INTEGER, deleted_at DATETIME',
    'soft_deletable_model_with_timestamps' => 'parent_model_id INTEGER, created_at DATETIME, updated_at DATETIME, deleted_at DATETIME',
    'not_soft_deletable_model_with_belongs_and_assocation_not_soft_deleted_validators' => 'parent_model_id INTEGER, soft_deletable_model_with_has_one_id INTEGER',
    'featureful_models' => 'deleted_at DATETIME, name VARCHAR(32)',
    'plain_models' => 'deleted_at DATETIME',
    'callback_models' => 'deleted_at DATETIME',
    'fail_callback_models' => 'deleted_at DATETIME',
    'related_models' => 'parent_model_id INTEGER, parent_model_with_counter_cache_column_id INTEGER, deleted_at DATETIME',
    'asplode_models' => 'parent_model_id INTEGER, deleted_at DATETIME',
    'employers' => 'name VARCHAR(32), deleted_at DATETIME',
    'employees' => 'deleted_at DATETIME',
    'jobs' => 'employer_id INTEGER NOT NULL, employee_id INTEGER NOT NULL, deleted_at DATETIME',
    'custom_column_models' => 'destroyed_at DATETIME',
    'custom_sentinel_models' => 'deleted_at DATETIME NOT NULL',
    'polymorphic_models' => 'parent_id INTEGER, parent_type STRING, deleted_at DATETIME',
    'non_soft_deletable_unique_models' => 'name VARCHAR(32), soft_deletable_with_non_soft_deletables_id INTEGER',
    'active_column_models' => 'deleted_at DATETIME, active BOOLEAN',
    'active_column_model_with_uniqueness_validations' => 'name VARCHAR(32), deleted_at DATETIME, active BOOLEAN',
    'soft_deletable_model_with_belongs_to_active_column_model_with_has_many_relationships' => 'name VARCHAR(32), deleted_at DATETIME, active BOOLEAN, active_column_model_with_has_many_relationship_id INTEGER',
    'active_column_model_with_has_many_relationships' => 'name VARCHAR(32), deleted_at DATETIME, active BOOLEAN',
    'without_default_scope_models' => 'deleted_at DATETIME'
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
    connection = ActiveRecord::Base.connection
    cleaner = ->(source) {
      ActiveRecord::Base.connection.execute "DELETE FROM #{source}"
    }

    if ActiveRecord::VERSION::MAJOR < 5
      connection.tables.each(&cleaner)
    else
      connection.data_sources.each(&cleaner)
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

  def test_soft_delete_behavior_for_plain_models_callbacks
    model = CallbackModel.new
    model.save
    model.remove_called_variables     # clear called callback flags
    model.soft_delete

    assert_nil model.instance_variable_get(:@update_callback_called)
    assert_nil model.instance_variable_get(:@save_callback_called)
    assert_nil model.instance_variable_get(:@validate_called)
    assert_nil model.instance_variable_get(:@destroy_callback_called)
    assert_nil model.instance_variable_get(:@after_destroy_callback_called)
    assert model.instance_variable_get(:@after_commit_callback_called)
    assert model.instance_variable_get(:@after_soft_delete_callback_called)
  end

  def test_delete_in_transaction_behavior_for_plain_models_callbacks
    model = CallbackModel.new
    model.save
    model.remove_called_variables     # clear called callback flags
    CallbackModel.transaction do
      model.soft_delete
    end

    assert_nil model.instance_variable_get(:@update_callback_called)
    assert_nil model.instance_variable_get(:@save_callback_called)
    assert_nil model.instance_variable_get(:@validate_called)
    assert_nil model.instance_variable_get(:@destroy_callback_called)
    assert_nil model.instance_variable_get(:@after_destroy_callback_called)
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

    assert_equal 2, SoftDeletableModel.only_deleted.joins(:parent_model).count
    assert_equal 1, parent1.soft_deletable_models.deleted.count
    assert_equal 0, parent1.soft_deletable_models.without_deleted.count
    p3 = SoftDeletableModel.create(:parent_model => parent1)
    assert_equal 2, parent1.soft_deletable_models.with_deleted.count
    assert_equal 1, parent1.soft_deletable_models.without_deleted.count
    assert_equal [p1, p3], parent1.soft_deletable_models.with_deleted
  end

  def test_only_deleted_with_joins
    c1 = ActiveColumnModelWithHasManyRelationship.create(name: 'Jacky')
    c2 = ActiveColumnModelWithHasManyRelationship.create(name: 'Thomas')
    p1 = SoftDeletableModelWithBelongsToActiveColumnModelWithHasManyRelationship.create(name: 'Hello', active_column_model_with_has_many_relationship: c1)

    c1.soft_delete
    assert_equal 1, ActiveColumnModelWithHasManyRelationship.count
    assert_equal 1, ActiveColumnModelWithHasManyRelationship.only_deleted.count
    assert_equal 1, ActiveColumnModelWithHasManyRelationship.only_deleted.joins(:soft_deletable_model_with_belongs_to_active_column_model_with_has_many_relationships).count
  end

  def test_soft_delete_behavior_for_custom_column_models
    model = CustomColumnModel.new
    assert_equal 0, model.class.count
    model.save!
    assert_nil model.destroyed_at
    assert_equal 1, model.class.count
    model.soft_delete

    assert_equal false, model.destroyed_at.nil?
    assert model.soft_deleted?

    assert_equal 0, model.class.count
    assert_equal 1, model.class.unscoped.count
    assert_equal 1, model.class.only_deleted.count
    assert_equal 1, model.class.deleted.count
  end

  def test_default_sentinel_value
    assert_nil SoftDeletableModel.soft_delete_sentinel_value
  end

  def test_without_default_scope_option
    model = WithoutDefaultScopeModel.create
    model.soft_delete
    assert_equal 1, model.class.count
    assert_equal 1, model.class.only_deleted.count
    assert_equal 0, model.class.where(deleted_at: nil).count
  end

  def test_active_column_model
    model = ActiveColumnModel.new
    assert_equal 0, model.class.count
    model.save!
    assert_nil model.deleted_at
    assert_equal true, model.active
    assert_equal 1, model.class.count
    model.soft_delete

    assert_equal false, model.deleted_at.nil?
    assert_nil model.active
    assert model.soft_deleted?

    assert_equal 0, model.class.count
    assert_equal 1, model.class.unscoped.count
    assert_equal 1, model.class.only_deleted.count
    assert_equal 1, model.class.deleted.count
  end

  def test_active_column_model_with_uniqueness_validation_only_checks_non_deleted_records
    a = ActiveColumnModelWithUniquenessValidation.create!(name: "A")
    a.soft_delete
    b = ActiveColumnModelWithUniquenessValidation.new(name: "A")
    assert b.valid?
  end

  def test_active_column_model_with_uniqueness_validation_still_works_on_non_deleted_records
    a = ActiveColumnModelWithUniquenessValidation.create!(name: "A")
    b = ActiveColumnModelWithUniquenessValidation.new(name: "A")
    refute b.valid?
  end

  def test_sentinel_value_for_custom_sentinel_models
    model = CustomSentinelModel.new
    assert_equal 0, model.class.count
    model.save!
    assert_equal DateTime.new(0), model.deleted_at
    assert_equal 1, model.class.count
    model.soft_delete

    assert DateTime.new(0) != model.deleted_at
    assert model.soft_deleted?

    assert_equal 0, model.class.count
    assert_equal 1, model.class.unscoped.count
    assert_equal 1, model.class.only_deleted.count
    assert_equal 1, model.class.deleted.count

    model.restore
    assert_equal DateTime.new(0), model.deleted_at
    assert !model.soft_deleted?

    assert_equal 1, model.class.count
    assert_equal 1, model.class.unscoped.count
    assert_equal 0, model.class.only_deleted.count
    assert_equal 0, model.class.deleted.count
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

  def test_chaining_for_soft_deletable_models
    scope = FeaturefulModel.where(:name => "foo").only_deleted
    assert_equal({'name' => "foo"}, scope.where_values_hash)
  end

  def test_only_deleted_scope_for_soft_deletable_models
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

  def test_soft_delete_not_propagated_on_associations
    parent = ParentModel.create
    child = parent.very_related_models.create

    parent.soft_delete

    assert_equal false, parent.deleted_at.nil?
    assert_nil child.reload.deleted_at
  end

  def test_restore_not_propagated_on_associations
    parent = ParentModel.create
    child = parent.very_related_models.create

    parent.soft_delete
    child.soft_delete

    assert_equal false, parent.deleted_at.nil?
    assert child.soft_deleted?

    parent.restore!
    assert_nil parent.deleted_at
    assert_equal false, child.reload.deleted_at.nil?
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

  def test_updated_at_modification_on_soft_delete
    soft_deletable_model = SoftDeletableModelWithTimestamp.create(:parent_model => ParentModel.create, :updated_at => 1.day.ago)
    assert soft_deletable_model.updated_at < 10.minutes.ago
    soft_deletable_model.soft_delete
    assert soft_deletable_model.updated_at > 10.minutes.ago
  end

  def test_updated_at_modification_on_restore
    parent1 = ParentModel.create
    pt1 = SoftDeletableModelWithTimestamp.create(:parent_model => parent1)
    SoftDeletableModelWithTimestamp.record_timestamps = false
    pt1.update_columns(created_at: 20.years.ago, updated_at: 10.years.ago, deleted_at: 10.years.ago)
    SoftDeletableModelWithTimestamp.record_timestamps = true
    assert pt1.updated_at < 10.minutes.ago
    refute pt1.deleted_at.nil?
    pt1.restore!
    assert pt1.deleted_at.nil?
    assert pt1.updated_at > 10.minutes.ago
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

  # Ensure that we're checking parent_type when restoring
  def test_missing_restore_recursive_on_polymorphic_has_one_association
    parent = ParentModel.create
    polymorphic = PolymorphicModel.create(parent_id: parent.id, parent_type: 'SoftDeletableModel')

    parent.soft_delete
    polymorphic.soft_delete

    assert_equal 0, polymorphic.class.count

    parent.restore(recursive: true)

    assert_equal 0, polymorphic.class.count
  end


  def test_counter_cache_column_update_on_destroy
    parent_model_with_counter_cache_column = ParentModelWithCounterCacheColumn.create
    related_model = parent_model_with_counter_cache_column.related_models.create

    assert_equal 1, parent_model_with_counter_cache_column.reload.related_models_count
    related_model.soft_delete
    assert_equal 0, parent_model_with_counter_cache_column.reload.related_models_count
  end

  def test_callbacks_for_counter_cache_column_update_on_destroy
    parent_model_with_counter_cache_column = ParentModelWithCounterCacheColumn.create
    related_model = parent_model_with_counter_cache_column.related_models.create

    assert_nil related_model.instance_variable_get(:@after_soft_delete_callback_called)

    related_model.soft_delete

    assert related_model.instance_variable_get(:@after_soft_delete_callback_called)
  end

  def test_uniqueness_for_non_soft_delete_associated
    parent_model = SoftDeletableWithNonSoftDeletables.create
    related = parent_model.non_soft_deletable_unique_models.create
    # will raise exception if model is not checked for soft deletability
    related.valid?
  end

  def test_assocation_not_soft_deleted_validator
    not_soft_deleteable_model =
    NotSoftDeletableModelWithBelongsAndAssocationNotSoftDeletedValidator.create
    parent_model = ParentModel.create
    assert not_soft_deleteable_model.valid?

    not_soft_deleteable_model.parent_model = parent_model
    assert not_soft_deleteable_model.valid?
    parent_model.soft_delete
    assert !not_soft_deleteable_model.valid?
    assert not_soft_deleteable_model.errors.full_messages.include? "Parent model has been soft-deleted"
  end

  def test_counter_cache_column_on_double_soft_delete
    parent_model_with_counter_cache_column = ParentModelWithCounterCacheColumn.create
    related_model = parent_model_with_counter_cache_column.related_models.create

    related_model.soft_delete
    related_model.soft_delete
    assert_equal 0, parent_model_with_counter_cache_column.reload.related_models_count
  end

  def test_counter_cache_column_on_double_restore
    parent_model_with_counter_cache_column = ParentModelWithCounterCacheColumn.create
    related_model = parent_model_with_counter_cache_column.related_models.create

    related_model.soft_delete
    related_model.restore
    related_model.restore
    assert_equal 1, parent_model_with_counter_cache_column.reload.related_models_count
  end

  def test_counter_cache_column_on_restore
    parent_model_with_counter_cache_column = ParentModelWithCounterCacheColumn.create
    related_model = parent_model_with_counter_cache_column.related_models.create

    related_model.soft_delete
    assert_equal 0, parent_model_with_counter_cache_column.reload.related_models_count
    related_model.restore
    assert_equal 1, parent_model_with_counter_cache_column.reload.related_models_count
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

  before_soft_delete { |_|
    if ActiveRecord::VERSION::MAJOR < 5
      false
    else
      throw :abort
    end
  }
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

class CustomColumnModel < ActiveRecord::Base
  acts_as_soft_deletable column: :destroyed_at
end

class CustomSentinelModel < ActiveRecord::Base
  acts_as_soft_deletable sentinel_value: DateTime.new(0)
end

class WithoutDefaultScopeModel < ActiveRecord::Base
  acts_as_soft_deletable without_default_scope: true
end

class ActiveColumnModel < ActiveRecord::Base
  acts_as_soft_deletable column: :active, sentinel_value: true

  def soft_delete_restore_attributes
    {
      deleted_at: nil,
      active: true
    }
  end

  def soft_delete_attributes
    {
      deleted_at: current_time_from_proper_timezone,
      active: nil
    }
  end
end

class ActiveColumnModelWithUniquenessValidation < ActiveRecord::Base
  validates :name, :uniqueness => true
  acts_as_soft_deletable column: :active, sentinel_value: true

  def soft_delete_restore_attributes
    {
      deleted_at: nil,
      active: true
    }
  end

  def soft_delete_destroy_attributes
    {
      deleted_at: current_time_from_proper_timezone,
      active: nil
    }
  end
end

class ActiveColumnModelWithHasManyRelationship < ActiveRecord::Base
  has_many :soft_deletable_model_with_belongs_to_active_column_model_with_has_many_relationships
  acts_as_soft_deletable column: :active, sentinel_value: true

  def soft_delete_restore_attributes
    {
      deleted_at: nil,
      active: true
    }
  end

  def soft_delete_destroy_attributes
    {
      deleted_at: current_time_from_proper_timezone,
      active: nil
    }
  end
end

class SoftDeletableModelWithBelongsToActiveColumnModelWithHasManyRelationship < ActiveRecord::Base
  belongs_to :active_column_model_with_has_many_relationship

  acts_as_soft_deletable column: :active, sentinel_value: true

  def soft_delete_restore_attributes
    {
      deleted_at: nil,
      active: true
    }
  end

  def soft_delete_destroy_attributes
    {
      deleted_at: current_time_from_proper_timezone,
      active: nil
    }
  end
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

class SoftDeletableModelWithoutObservers < SoftDeletableModel
  self.class.send(remove_method :notify_observers) if method_defined?(:notify_observers)
end

class SoftDeletableModelWithTimestamp < ActiveRecord::Base
  belongs_to :parent_model
  acts_as_soft_deletable
end

class NotSoftDeletableModelWithBelongsAndAssocationNotSoftDeletedValidator < ActiveRecord::Base
    acts_as_soft_deletable
    belongs_to :parent_model
    validates :parent_model, association_not_soft_deleted: true
end

class AsplodeModel < ActiveRecord::Base
  acts_as_soft_deletable
  before_soft_delete do |r|
    raise StandardError, 'ASPLODE!'
  end
end

class NoConnectionModel < ActiveRecord::Base
end

class PolymorphicModel < ActiveRecord::Base
  acts_as_soft_deletable
  belongs_to :parent, polymorphic: true
end
