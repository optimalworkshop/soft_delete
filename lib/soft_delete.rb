require 'active_record' unless defined? ActiveRecord

module SoftDelete
  @@default_sentinel_value = nil

  # Change default_sentinel_value in a rails initializer
  def self.default_sentinel_value=(val)
    @@default_sentinel_value = val
  end

  def self.default_sentinel_value
    @@default_sentinel_value
  end

  def self.included(klazz)
    klazz.extend Query
  end

  module Query
    def soft_deletable? ; true ; end

    def with_deleted
      unscope(where: soft_delete_column)
    end

    def only_deleted
      with_deleted.where.not(deleted_at: nil)

      if soft_delete_sentinel_value.nil?
        return with_deleted.where.not(soft_delete_column => soft_delete_sentinel_value)
      end
      # if soft_delete_sentinel_value is not null, then it is possible that
      # some deleted rows will hold a null value in the soft_delete column
      # these will not match != sentinel value because "NULL != value" is
      # NULL under the sql standard
      # Scoping with the table_name is mandatory to avoid ambiguous errors when joining tables.
      scoped_quoted_soft_delete_column = "#{self.table_name}.#{connection.quote_column_name(soft_delete_column)}"
      with_deleted.where("#{scoped_quoted_soft_delete_column} IS NULL OR #{scoped_quoted_soft_delete_column} != ?", soft_delete_sentinel_value)
    end
    alias :deleted :only_deleted

    def restore(id_or_ids, opts = {})
      ids = Array(id_or_ids).flatten
      any_object_instead_of_id = ids.any? { |id| ActiveRecord::Base === id }
      if any_object_instead_of_id
        ids.map! { |id| ActiveRecord::Base === id ? id.id : id }
        ActiveSupport::Deprecation.warn("You are passing an instance of ActiveRecord::Base to `restore`. " \
                                        "Please pass the id of the object by calling `.id`")
      end
      ids.map { |id| only_deleted.find(id).restore!(opts) }
    end
  end

  def soft_delete
    transaction do
      run_callbacks(:soft_delete) do
        @_disable_counter_cache = deleted?
        result = soft_delete_touch
        next result unless result
        each_counter_cached_associations do |association|
          next unless send(association.reflection.name)
          association.decrement_counters
        end
        @_disable_counter_cache = false
        result
      end
    end
  end

  def soft_delete!
    soft_delete ||
      raise(ActiveRecord::RecordNotDestroyed.new("Failed to destroy the record", self))
  end

  def restore!(opts = {})
    self.class.transaction do
      run_callbacks(:restore) do
        @_disable_counter_cache = !soft_deleted?
        write_attribute soft_delete_column, soft_delete_sentinel_value
        update_columns(soft_delete_restore_attributes)
        each_counter_cached_associations do |association|
          if send(association.reflection.name)
            association.increment_counters
          end
        end
        @_disable_counter_cache = false
      end
    end

    self
  end
  alias :restore :restore!

  def soft_deleted?
    send(soft_delete_column) != soft_delete_sentinel_value
  end
  alias :deleted? :soft_deleted?

  private

  def each_counter_cached_associations
    !(defined?(@_disable_counter_cache) && @_disable_counter_cache) ? super : []
  end

  def soft_delete_restore_attributes
    {
      soft_delete_column => soft_delete_sentinel_value
    }.merge(timestamp_attributes_with_current_time)
  end

  def soft_delete_attributes
    {
      soft_delete_column => current_time_from_proper_timezone
    }.merge(timestamp_attributes_with_current_time)
  end

  def timestamp_attributes_with_current_time
    timestamp_attributes_for_update_in_model.each_with_object({}) { |attr, hash| hash[attr] = current_time_from_proper_timezone }
  end

  def soft_delete_touch
    raise ActiveRecord::ReadOnlyRecord, "#{self.class} is marked as readonly" if readonly?
    if persisted?
      # if a transaction exists, add the record so that after_commit
      # callbacks can be run
      add_to_transaction
      update_columns(soft_delete_attributes)
    elsif !frozen?
      assign_attributes(soft_delete_attributes)
    end

    self
  end
end

ActiveSupport.on_load(:active_record) do
  class ActiveRecord::Base
    def self.acts_as_soft_deletable(options={})
      define_model_callbacks :restore, :soft_delete
      include SoftDelete
      class_attribute :soft_delete_column, :soft_delete_sentinel_value

      self.soft_delete_column = (options[:column] || :deleted_at).to_s
      self.soft_delete_sentinel_value = options.fetch(:sentinel_value) { SoftDelete.default_sentinel_value }

      def self.soft_delete_scope
        where(soft_delete_column => soft_delete_sentinel_value)
      end
      class << self; alias_method :without_deleted, :soft_delete_scope end

      unless options[:without_default_scope]
        default_scope { soft_delete_scope }
      end

      before_restore {
        self.class.notify_observers(:before_restore, self) if self.class.respond_to?(:notify_observers)
      }
      after_restore {
        self.class.notify_observers(:after_restore, self) if self.class.respond_to?(:notify_observers)
      }
      before_soft_delete {
        self.class.notify_observers(:before_soft_delete, self) if self.class.respond_to?(:notify_observers)
      }
      after_soft_delete {
        self.class.notify_observers(:after_soft_delete, self) if self.class.respond_to?(:notify_observers)
      }
    end

    def self.soft_deletable? ; false ; end
    def soft_deletable? ; self.class.soft_deletable? ; end

    private

    def soft_delete_column
      self.class.soft_delete_column
    end

    def soft_delete_sentinel_value
      self.class.soft_delete_sentinel_value
    end
  end
end

module ActiveRecord
  module Validations
    module UniquenessSoftDeleteValidator
      protected
      def build_relation(klass, *args)
        relation = super
        return relation unless klass.respond_to?(:soft_delete_column)
        arel_soft_delete_scope = klass.arel_table[klass.soft_delete_column].eq(klass.soft_delete_sentinel_value)
        if ActiveRecord::VERSION::STRING >= "5.0"
          relation.where(arel_soft_delete_scope)
        else
          relation.and(arel_soft_delete_scope)
        end
      end
    end

    class UniquenessValidator < ActiveModel::EachValidator
      prepend UniquenessSoftDeleteValidator
    end

    class AssociationNotSoftDeletedValidator < ActiveModel::EachValidator
      def validate_each(record, attribute, value)
        # if association is soft destroyed, add an error
        if value.present? && value.soft_deleted?
          record.errors[attribute] << 'has been soft-deleted'
        end
      end
    end
  end
end
