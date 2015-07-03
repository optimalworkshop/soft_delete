require 'active_record' unless defined? ActiveRecord

module SoftDelete

  def self.included(klazz)
    klazz.extend Query
    klazz.extend Callbacks
  end

  module Query
    def soft_delete? ; true ; end

    def with_deleted
      if ActiveRecord::VERSION::STRING >= "4.1"
        unscope where: :deleted_at
      else
        scoped.tap { |x| x.default_scoped = false }
      end
    end

    def only_deleted
      if ActiveRecord::VERSION::STRING >= "4.1"
        with_deleted.where.not(deleted_at: nil)
      else
        with_deleted.where("#{self.table_name}.deleted_at IS NOT NULL") # TODO: RGJB: Escaped table name? Also, put back in Rails 4.1 version.
      end
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

  module Callbacks
    def self.extended(klazz)
      [:restore, :soft_delete].each do |callback_name|
        klazz.define_callbacks callback_name

        klazz.define_singleton_method("before_#{callback_name}") do |*args, &block|
          set_callback(callback_name, :before, *args, &block)
        end

        klazz.define_singleton_method("around_#{callback_name}") do |*args, &block|
          set_callback(callback_name, :around, *args, &block)
        end

        klazz.define_singleton_method("after_#{callback_name}") do |*args, &block|
          set_callback(callback_name, :after, *args, &block)
        end
      end
    end
  end

  def soft_delete!
    run_callbacks(:soft_delete) do
      touch_deleted_at
    end

    self
  end
  alias :soft_delete :soft_delete!

  def restore!(opts = {})
    self.class.transaction do
      run_callbacks(:restore) do
        # Fixes a bug where the build would error because attributes were frozen.
        # This only happened on Rails versions earlier than 4.1.
        noop_if_frozen = ActiveRecord.version < Gem::Version.new("4.1")
        if (noop_if_frozen && !@attributes.frozen?) || !noop_if_frozen
          write_attribute paranoia_column, paranoia_sentinel_value
          update_column paranoia_column, paranoia_sentinel_value
        end
        restore_associated_records if opts[:recursive]
      end
    end

    self
  end
  alias :restore :restore!

  def soft_deleted?
    deleted_at?
  end
  alias :deleted? :soft_deleted?

  private

    def touch_deleted_at
      raise ActiveRecord::ReadOnlyRecord, "#{self.class} is marked as readonly" if readonly?
      if persisted?
        touch(:deleted_at)
      elsif !frozen?
        write_attribute(:deleted_at, Time.zone.now)
      end

      self
    end

end

class ActiveRecord::Base
  def self.acts_as_soft_deletable(options={})
    include SoftDelete

    def self.soft_delete_scope
      where(deleted_at: nil)
    end
    default_scope { soft_delete_scope }

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

  def self.soft_delete? ; false ; end
  def soft_delete? ; self.class.soft_delete? ; end

end

module ActiveRecord
  module Validations
    class UniquenessValidator < ActiveModel::EachValidator
      protected
      def build_relation_with_soft_delete(klass, table, attribute, value)
        relation = build_relation_without_soft_delete(klass, table, attribute, value)
        if klass.soft_delete?
          relation.merge(klass.soft_delete_scope)
        else
          relation
        end
      end
      alias_method_chain :build_relation, :soft_delete
    end
  end
end
