# Copyright (c) 2007, 2008 Pythonic Pty Ltd
# http://www.pythonic.com.au/

require "test_helper"

class NestedIntervalTestMigration < ActiveRecord::Migration
  def self.up
    create_table :nested_interval_test_regions do |t|
      t.integer :parent_id
      t.integer :lftp, :null => false
      t.integer :lftq, :null => false
      t.string :name, :null => false
    end
  end

  def self.down
    drop_table :nested_interval_test_regions
  end
end

NestedIntervalTestMigration.migrate :up

at_exit do
  at_exit do
    NestedIntervalTestMigration.migrate :down
  end
end

class NestedIntervalTestRegion < ActiveRecord::Base
  acts_as_nested_interval
end

class NestedIntervalTest < Test::Unit::TestCase
  def test_modular_inverse
    assert_equal 8, -8.inverse(9)
    assert_equal 4, -7.inverse(9)
    assert_nil -6.inverse(9)
    assert_equal 2, -5.inverse(9)
    assert_equal 7, -4.inverse(9)
    assert_nil -3.inverse(9)
    assert_equal 5, -2.inverse(9)
    assert_equal 1, -1.inverse(9)
    assert_nil 0.inverse(9)
    assert_equal 1, +1.inverse(9)
    assert_equal 5, +2.inverse(9)
    assert_nil +3.inverse(9)
    assert_equal 7, +4.inverse(9)
    assert_equal 2, +5.inverse(9)
    assert_nil +6.inverse(9)
    assert_equal 4, +7.inverse(9)
    assert_equal 8, +8.inverse(9)
  end

  def test_create_root
    earth = NestedIntervalTestRegion.create :name => "Earth"
    assert_equal [0, 1], [earth.lftp, earth.lftq]
    assert_equal [1, 1], [earth.rgtp, earth.rgtq]
    assert_equal earth, NestedIntervalTestRegion.root
  end

  def test_create_first_child
    earth = NestedIntervalTestRegion.create :name => "Earth"
    oceania = NestedIntervalTestRegion.create :name => "Oceania", :parent => earth
    assert_equal [1, 2], [oceania.lftp, oceania.lftq]
    assert_equal [1, 1], [oceania.rgtp, oceania.rgtq]
  end

  def test_create_second_child
    earth = NestedIntervalTestRegion.create :name => "Earth"
    oceania = NestedIntervalTestRegion.create :name => "Oceania", :parent => earth
    australia = NestedIntervalTestRegion.create :name => "Australia", :parent => oceania
    new_zealand = NestedIntervalTestRegion.create :name => "New Zealand", :parent => oceania
    assert_equal [2, 3], [australia.lftp, australia.lftq]
    assert_equal [1, 1], [australia.rgtp, australia.rgtq]
    assert_equal [3, 5], [new_zealand.lftp, new_zealand.lftq]
    assert_equal [2, 3], [new_zealand.rgtp, new_zealand.rgtq]
  end

  def test_append_child
    earth = NestedIntervalTestRegion.create :name => "Earth"
    oceania = NestedIntervalTestRegion.new :name => "Oceania"
    earth.children << oceania
    assert_equal [1, 2], [oceania.lftp, oceania.lftq]
    assert_equal [1, 1], [oceania.rgtp, oceania.rgtq]
  end

  def test_ancestors
    earth = NestedIntervalTestRegion.create :name => "Earth"
    oceania = NestedIntervalTestRegion.create :name => "Oceania", :parent => earth
    australia = NestedIntervalTestRegion.create :name => "Australia", :parent => oceania
    new_zealand = NestedIntervalTestRegion.create :name => "New Zealand", :parent => oceania
    assert_equal [], earth.ancestors.sort_by(&:id)
    assert_equal [earth], oceania.ancestors.sort_by(&:id)
    assert_equal [earth, oceania], australia.ancestors.sort_by(&:id)
    assert_equal [earth, oceania], new_zealand.ancestors.sort_by(&:id)
  end

  def test_descendants
    earth = NestedIntervalTestRegion.create :name => "Earth"
    oceania = NestedIntervalTestRegion.create :name => "Oceania", :parent => earth
    australia = NestedIntervalTestRegion.create :name => "Australia", :parent => oceania
    new_zealand = NestedIntervalTestRegion.create :name => "New Zealand", :parent => oceania
    assert_equal [oceania, australia, new_zealand], earth.descendants.sort_by(&:id)
    assert_equal [australia, new_zealand], oceania.descendants.sort_by(&:id)
    assert_equal [], australia.descendants.sort_by(&:id)
    assert_equal [], new_zealand.descendants.sort_by(&:id)
  end

  def test_depth
    earth = NestedIntervalTestRegion.create :name => "Earth"
    oceania = NestedIntervalTestRegion.create :name => "Oceania", :parent => earth
    australia = NestedIntervalTestRegion.create :name => "Australia", :parent => oceania
    new_zealand = NestedIntervalTestRegion.create :name => "New Zealand", :parent => oceania
    assert_equal 0, earth.depth
    assert_equal 1, oceania.depth
    assert_equal 2, australia.depth
    assert_equal 2, new_zealand.depth
  end

  def test_move
    earth = NestedIntervalTestRegion.create :name => "Earth"
    oceania = NestedIntervalTestRegion.create :name => "Oceania", :parent => earth
    australia = NestedIntervalTestRegion.create :name => "Australia", :parent => oceania
    new_zealand = NestedIntervalTestRegion.create :name => "New Zealand", :parent => oceania
    assert_raise ActiveRecord::RecordInvalid do
      oceania.parent = oceania
      oceania.save!
    end
    assert_raise ActiveRecord::RecordInvalid do
      oceania.parent = australia
      oceania.save!
    end
    pacific = NestedIntervalTestRegion.create :name => "Pacific", :parent => earth
    assert_equal [1, 3], [pacific.lftp, pacific.lftq]
    assert_equal [1, 2], [pacific.rgtp, pacific.rgtq]
    oceania.parent = pacific
    oceania.save!
    assert_equal [0, 1], [earth.lftp, earth.lftq]
    assert_equal [1, 1], [earth.rgtp, earth.rgtq]
    assert_equal [1, 3], [pacific.lftp, pacific.lftq]
    assert_equal [1, 2], [pacific.rgtp, pacific.rgtq]
    assert_equal [2, 5], [oceania.lftp, oceania.lftq]
    assert_equal [1, 2], [oceania.rgtp, oceania.rgtq]
    australia.reload
    assert_equal [3, 7], [australia.lftp, australia.lftq]
    assert_equal [1, 2], [australia.rgtp, australia.rgtq]
    new_zealand.reload
    assert_equal [5, 12], [new_zealand.lftp, new_zealand.lftq]
    assert_equal [3, 7], [new_zealand.rgtp, new_zealand.rgtq]
  end

  def test_destroy
    earth = NestedIntervalTestRegion.create :name => "Earth"
    oceania = NestedIntervalTestRegion.create :name => "Oceania", :parent => earth
    australia = NestedIntervalTestRegion.create :name => "Australia", :parent => oceania
    new_zealand = NestedIntervalTestRegion.create :name => "New Zealand", :parent => oceania
    oceania.destroy
    assert_equal [], earth.descendants
  end

  def test_limits
    region = NestedIntervalTestRegion.create :name => ""
    22.times do
      NestedIntervalTestRegion.create :name => "", :parent => region
      region = NestedIntervalTestRegion.create :name => "", :parent => region
    end
    region.descendants
  end
end
