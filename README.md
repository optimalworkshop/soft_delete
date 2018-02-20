# Soft Delete [![Build Status](https://semaphoreci.com/api/v1/projects/9e05f647-837d-45c2-ac6c-c3c4d83bbdea/475805/badge.svg)](https://semaphoreci.com/optimalworkshop/soft_delete)


Soft Delete is a stripped down version of [Paranoia](https://github.com/radar/paranoia).

SoftDelete is a stripped down version of Paranoia which doesn't override destroy on any Active Record objects. You would use this plugin / gem if you wish to *hide* records by called `soft_delete` on them without needing to highjack the `destroy` method and without playing with `dependent: :destroy`. SoftDelete does this by setting the `deleted_at` field to the current time when you soft delete a record, and hides it by scoping all queries on your model to only include records which do not have `deleted_at` set. If you would like to be able to call `destroy` and have the soft deletion cascaded through dependents then please use [Paranoia](https://github.com/radar/paranoia).

SoftDelete does not cascade through dependent associations.

## Installation & Usage

For Rails versions older than 4.2, please use version 1 of Soft Delete:

``` ruby
gem "soft_delete", :github => "optimalworkshop/soft_delete", :branch => "rails3"
```
or
``` ruby
gem "soft_delete", :github => "optimalworkshop/soft_delete", :branch => "rails4"
```


For Rails 4.2 and 5, please use version 4 of Soft Delete:

``` ruby
gem "soft_delete", :github => "optimalworkshop/soft_delete", :tag => "v4.0.0"
```


Then run:

``` shell
bundle install
```

Updating is as simple as `bundle update soft_delete`.

#### Run your migrations for the desired models

Run:

``` shell
rails generate migration AddDeletedAtToClients deleted_at:datetime:index
```

and now you have a migration

``` ruby
class AddDeletedAtToClients < ActiveRecord::Migration
  def change
    add_column :clients, :deleted_at, :datetime
    add_index :clients, :deleted_at
  end
end
```

### Usage

#### In your model:

``` ruby
class Client < ActiveRecord::Base
  acts_as_soft_deletable

  # ...
end
```

Hey presto, it's there! Calling `soft_delete` will now set the `deleted_at` column:


``` ruby
>> client.deleted_at
# => nil
>> client.soft_delete
# => client
>> client.deleted_at
# => [current timestamp]
```

If you want to use a column other than `deleted_at`, you can pass it as an option:

``` ruby
class Client < ActiveRecord::Base
  acts_as_soft_deletable column: :destroyed_at

  ...
end
```

If you want to skip adding the default scope:

``` ruby
class Client < ActiveRecord::Base
  acts_as_paranoid without_default_scope: true

  ...
end
```

If you want to access soft-deleted associations, override the getter method:

``` ruby
def product
  Product.unscoped { super }
end
```

If you want to include associated soft-deleted objects in Rails 4+, you can (un)scope the association:

``` ruby
class Person < ActiveRecord::Base
  belongs_to :group, -> { with_deleted }
end

Person.includes(:group).all
```

If you want to include associated soft-deleted objects, you can (un)scope the association:

``` ruby
class Person < ActiveRecord::Base
  belongs_to :group, -> { with_deleted }
end

Person.includes(:group).all
```

If you want to find all records, even those which are deleted:

``` ruby
Client.with_deleted
```

If you want to exclude deleted records, when not able to use the default_scope (e.g. when using without_default_scope):

``` ruby
Client.without_deleted
```

If you want to find only the deleted records:

``` ruby
Client.only_deleted
```

If you want to check if a record is soft-deleted:

``` ruby
client.soft_deleted?
# or
client.deleted?
```

If you want to restore a record:

``` ruby
Client.restore(id)
# or
client.restore
```

If you want to restore a whole bunch of records:

``` ruby
Client.restore([id1, id2, ..., idN])
```

Note that by default soft_delete will not prevent that a soft deleted object can't be associated with another object of a different model.
A Rails validator is provided should you require this functionality:
  ``` ruby
validates :some_assocation, association_not_soft_deleted: true
```
This validator makes sure that `some_assocation` is not soft deleted. If the object is soft deleted the main object is rendered invalid and an validation error is added.

For more information, please look at the tests.

#### About indexes:

Beware that you should adapt all your indexes for them to work as fast as previously.
For example,

``` ruby
add_index :clients, :group_id
add_index :clients, [:group_id, :other_id]
```

should be replaced with

``` ruby
add_index :clients, :group_id, where: "deleted_at IS NULL"
add_index :clients, [:group_id, :other_id], where: "deleted_at IS NULL"
```

Of course, this is not necessary for the indexes you always use in association with `with_deleted` or `only_deleted`.

##### Unique Indexes

Because NULL != NULL in standard SQL, we can not simply create a unique index
on the deleted_at column and expect it to enforce that there only be one record
with a certain combination of values.

If your database supports them, good alternatives include partial indexes
(above) and indexes on computed columns. E.g.

``` ruby
add_index :clients, [:group_id, 'COALESCE(deleted_at, false)'], unique: true
```

If not, an alternative is to create a separate column which is maintained
alongside deleted_at for the sake of enforcing uniqueness. To that end,
soft_delete makes use of two method to make its delete and restore actions:
soft_delete_restore_attributes and soft_delete_attributes.

``` ruby
add_column :clients, :active, :boolean
add_index :clients, [:group_id, :active], unique: true

class Client < ActiveRecord::Base
  # optionally have soft_delete make use of your unique column, so that
  # your lookups will benefit from the unique index
  acts_as_paranoid column: :active, sentinel_value: true

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
```

## Callbacks

SoftDelete provides few callbacks. It triggers `soft_delete` callback when the record is marked as deleted. It also calls `restore` callback when record is restored via SoftDelete.
The `destroy` callback behaviour remains unchanged.

For example if you want to index you records in some search engine you can do like this:

```ruby
class Product < ActiveRecord::Base
  acts_as_soft_deletable

  after_soft_delete  :update_document_in_search_engine
  after_restore      :update_document_in_search_engine
  after_destroy      :remove_document_from_search_engine
end
```

You can use these events just like regular Rails callbacks with before, after and around hooks.

## License

This gem is released under the MIT license.
