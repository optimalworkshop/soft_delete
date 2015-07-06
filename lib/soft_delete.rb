require 'active_record' unless defined? ActiveRecord

module SoftDelete

  def self.included(klazz)
    klazz.extend Query
    klazz.extend Callbacks
  end

  module Query
    def soft_deletable? ; true ; end

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
        with_deleted.where("#{self.quoted_table_name}.deleted_at IS NOT NULL")
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
        klazz.define_model_callbacks :"#{callback_name}"
      end
    end
  end

  def soft_delete!
    transaction do
      run_callbacks(:soft_delete) do
        result = touch_deleted_at
        if result && ActiveRecord::VERSION::STRING >= '4.2'
          each_counter_cached_associations do |association|
            if send(association.reflection.name)
              association.decrement_counters
            end
          end
        end
        result
      end
    end
  end
  alias :soft_delete :soft_delete!

  def restore!(opts = {})
    self.class.transaction do
      run_callbacks(:restore) do
        # Fixes a bug where the build would error because attributes were frozen.
        # This only happened on Rails versions earlier than 4.1.
        noop_if_frozen = ActiveRecord::VERSION::STRING < "4.1"
        if (noop_if_frozen && !@attributes.frozen?) || !noop_if_frozen
          write_attribute :deleted_at, nil
          update_column :deleted_at, nil
        end
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
        write_attribute(:deleted_at, current_time_from_proper_timezone)
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

  def self.soft_deletable? ; false ; end
  def soft_deletable? ; self.class.soft_deletable? ; end

end
