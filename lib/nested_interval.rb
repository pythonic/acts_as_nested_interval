# Copyright (c) 2007, 2008 Pythonic Pty Ltd
# http://www.pythonic.com.au/

class Integer
  # Returns modular multiplicative inverse.
  # Examples:
  #   2.inverse(7) # => 4
  #   4.inverse(7) # => 2
  def inverse(m)
    u, v = m, self
    x, y = 0, 1
    while v != 0
      q, r = u.divmod(v)
      x, y = y, x - q * y
      u, v = v, r
    end
    if u.abs == 1
      x < 0 ? x + m : x
    end
  end
end

module ActiveRecord::Acts
  module NestedInterval
    def self.included(base)
      base.extend(ClassMethods)
    end

    # This act implements a nested-interval tree. You can find all descendants
    # or all ancestors with just one select query. You can insert and delete
    # records without a full table update.

    # This act requires parent_id, lftp and lftq integer columns.

    # Example:
    #   create_table :regions do |t|
    #     t.integer :parent_id
    #     t.integer :lftp, :null => false
    #     t.integer :lftq, :null => false
    #     t.string :name, :null => false
    #   end

    # This act provides this class method:
    #   root -- returns root of tree.

    # This act provides these instance methods:
    #   parent -- returns parent of record.
    #   children -- returns children of record.
    #   descendants -- returns descendants of record.
    #   ancestors -- returns ancestors of record.
    #   depth -- returns depth of record.

    # Example:
    #   class Region < ActiveRecord::Base
    #     acts_as_nested_interval
    #   end

    #   earth = Region.create :name => "Earth"
    #   oceania = Region.create :name => "Oceania", :parent => earth
    #   australia = Region.create :name => "Australia", :parent => oceania
    #   new_zealand = Region.new :name => "New Zealand"
    #   oceania.children << new_zealand
    #   earth.descendants # => [oceania, australia, new_zealand]
    #   earth.children # => [oceania]
    #   oceania.children # => [australia, new_zealand]
    #   oceania.depth # => 1
    #   australia.parent # => oceania
    #   new_zealand.ancestors # => [earth, oceania]
    #   Region.root # => earth

    # The "mediant" of two rationals is the rational with the sum of the two
    # numerators for the numerator, and the sum of the two denominators for
    # the denominator (where the denominators are positive). The mediant is
    # numerically between the two rationals. Example: 3 / 5 is the mediant of
    # 1 / 2 and 2 / 3, and 1 / 2 < 3 / 5 < 2 / 3.

    # Each record "covers" a half-open interval (lftp / lftq, rgtp / rgtq].
    # The tree root covers (0 / 1, 1 / 1]. The first child of a record covers
    # interval (mediant{lftp / lftq, rgtp / rgtq}, rgtp / rgtq]; the next child
    # covers interval (mediant{lftp / lftq, mediant{lftp / lftq, rgtp / rgtq}},
    #                    mediant{lftp / lftq, rgtp / rgtq}].

    # With this construction each lftp and lftq are relatively prime and the
    # identity lftq * rgtp = 1 + lftp * rgtq holds.

    # Example:
    #   earth covers (0 / 1, 1 / 1]
    #   oceania covers (1 / 2, 1 / 1]
    #   australia covers (2 / 3, 1 / 1]
    #   new zealand covers (3 / 5, 2 / 3]

    #          0/1                           1/2   3/5 2/3                 1/1
    # earth     (-----------------------------------------------------------]
    # oceania                                 (-----------------------------]
    # australia                                         (-------------------]
    # new zealand                                   (---]

    # The descendants of a record are those records that cover subintervals
    # of the interval covered by the record, and the ancestors are those
    # records that cover superintervals.

    # Only the left end of an interval needs to be stored, since the right end
    # can be calculated (with special exceptions) using the above identity:
    #   rgtp := x
    #   rgtq := (x * lftq - 1) / lftp
    # where x is the inverse of lftq modulo lftp.

    # Similarly, the left end of the interval covered by the parent of a
    # record can be calculated using the above identity:
    #   lftp := (x * lftp - 1) / lftq
    #   lftq := x
    # where x is the inverse of lftp modulo lftq.

    # To move a record from old.lftp, old.lftq to new.lftp, new.lftq, apply
    # this linear transform to lftp, lftq of all descendants:
    #   lftp := (old.lftq * new.rgtp - old.rgtq * new.lftp) * lftp
    #            + (old.rgtp * new.lftp - old.lftp * new.rgtp) * lftq
    #   lftq := (old.lftq * new.rgtq - old.rgtq * new.lftq) * lftp
    #            + (old.rgtp * new.lftq - old.lftp * new.rgtq) * lftq

    #  Example:
    #   pacific = Region.create :name => "Pacific", :parent => earth
    #   oceania.parent = pacific
    #   oceania.save!

    # Acknowledgement:
    #   http://arxiv.org/html/cs.DB/0401014 by Vadim Tropashko.

    module ClassMethods
      # The +options+ hash can include:
      # * <tt>:foreign_key</tt> -- the self-reference foreign key column name (default :parent_id).
      # * <tt>:scope</tt> -- an array of columns to scope independent trees.
      # * <tt>:lft_index</tt> -- whether to use (1.0 * lftp / lftq) index (default false).
      def acts_as_nested_interval(options = {})
        belongs_to :parent, :class_name => name, :foreign_key => options[:foreign_key] || :parent_id
        has_many :children, :class_name => name, :foreign_key => options[:foreign_key] || :parent_id, :dependent => :destroy
        cattr_accessor :nested_interval_scope
        cattr_accessor :nested_interval_lft_index
        self.nested_interval_scope = options[:scope]
        self.nested_interval_lft_index = options[:lft_index]
        class_eval do
          include ActiveRecord::Acts::NestedInterval::InstanceMethods
          alias_method_chain :create, :nested_interval
          alias_method_chain :destroy, :nested_interval
          alias_method_chain :update, :nested_interval
          class << self
            public :with_scope
            def root(options = {})
              with_scope :find => {:conditions => {:lftp => 0, :lftq => 1}} do
                find :first, options
              end
            end
          end
        end
      end
    end

    module InstanceMethods
      # Creates record.
      def create_with_nested_interval
        if parent_id.nil?
          self.lftp, self.lftq = 0, 1
        else
          self.lftp, self.lftq = parent.lock!.next_child_lft
        end
        create_without_nested_interval
      end

      # Destroys record.
      def destroy_with_nested_interval
        lock! rescue nil
        destroy_without_nested_interval
      end

      def with_nested_interval_scope(&block)
        if nested_interval_scope
          conditions = {}
          Array(nested_interval_scope).each do |column_name|
            conditions[column_name] = send(column_name)
          end
          self.class.with_scope :find => {:conditions => conditions}, &block
        else
          block.call
        end
      end

      def with_nested_interval_descendants_scope(&block)
        with_nested_interval_scope do
          quoted_table_name = self.class.quoted_table_name
          if nested_interval_lft_index
            conditions = %(#{lftp} < #{quoted_table_name}.lftp AND 1.0 * #{quoted_table_name}.lftp / #{quoted_table_name}.lftq BETWEEN #{1.0 * lftp / lftq} AND #{1.0 * rgtp / rgtq})
          elsif connection.adapter_name == "MySQL"
            conditions = %((#{quoted_table_name}.lftp != #{rgtp} OR #{quoted_table_name}.lftq != #{rgtq}) AND #{quoted_table_name}.lftp BETWEEN 1 + #{quoted_table_name}.lftq * #{lftp} DIV #{lftq} AND #{quoted_table_name}.lftq * #{rgtp} DIV #{rgtq})
          else
            conditions = %((#{quoted_table_name}.lftp != #{rgtp} OR #{quoted_table_name}.lftq != #{rgtq}) AND #{quoted_table_name}.lftp BETWEEN 1 + #{quoted_table_name}.lftq * CAST(#{lftp} AS BIGINT) / #{lftq} AND #{quoted_table_name}.lftq * CAST(#{rgtp} AS BIGINT) / #{rgtq})
          end
          self.class.with_scope :find => {:conditions => conditions}, &block
        end
      end

      # Returns all descendants.
      def descendants(options = {})
        with_nested_interval_descendants_scope do
          self.class.find :all, options
        end
      end

      # Updates record, updating descendants if parent association updated,
      # in which case caller should first acquire table lock.
      def update_with_nested_interval
        if parent_id.nil?
          self.lftp, self.lftq = 0, 1
        elsif !parent.updated?
          db_self = self.class.find id, :lock => true
          self.parent_id = db_self.parent_id
          self.lftp, self.lftq = db_self.lftp, db_self.lftq
        else
          # No locking in this case -- caller should have acquired table lock.
          db_self = self.class.find self.id
          db_parent = self.class.find parent_id
          if db_parent.lftp == db_self.lftp && db_parent.lftq == db_self.lftq \
              || db_parent.lftp > db_parent.lftq * db_self.lftp / db_self.lftq \
              && db_parent.lftp <= db_parent.lftq * db_self.rgtp / db_self.rgtq \
              && (db_parent.lftp != db_self.rgtp || db_parent.lftq != db_self.rgtq)
            errors.add :parent_id, "is descendant"
            raise ActiveRecord::RecordInvalid, self
          end
          self.lftp, self.lftq = parent.next_child_lft
          db_self.with_nested_interval_descendants_scope do
            mysql_tmp = "@" if connection.adapter_name == "MySQL"
            self.class.update_all %(
              lftp = #{db_self.lftq * rgtp - db_self.rgtq * lftp} * lftp
                      + #{db_self.rgtp * lftp - db_self.lftp * rgtp} * lftq,
              lftq = #{db_self.lftq * rgtq - db_self.rgtq * lftq} * #{mysql_tmp}lftp
                      + #{db_self.rgtp * lftq - db_self.lftp * rgtq} * lftq
            ), mysql_tmp && %(@lftp := lftp)
          end
        end
        update_without_nested_interval
      end

      # Returns all ancestors.
      def ancestors(options = {})
        sqls = [%(NULL)]
        lftp, lftq = self.lftp, self.lftq
        while lftp != 0
          x = lftp.inverse(lftq)
          lftp, lftq = (x * lftp - 1) / lftq, x
          sqls << %(lftq = #{lftq} AND lftp = #{lftp})
        end
        self.with_nested_interval_scope do
          self.class.with_scope :find => {:conditions => sqls * %( OR ), :order => %(lftp)} do
            self.class.find :all, options
          end
        end
      end

      # Returns depth by counting ancestors up to 0 / 1.
      def depth
        n = 0
        lftp, lftq = self.lftp, self.lftq
        while lftp != 0
          x = lftp.inverse(lftq)
          lftp, lftq = (x * lftp - 1) / lftq, x
          n += 1
        end
        n
      end

      # Returns numerator of right end of interval.
      def rgtp
        case lftp
        when 0
          1
        when 1
          1
        else
          lftq.inverse(lftp)
        end
      end

      # Returns denominator of right end of interval.
      def rgtq
        case lftp
        when 0
          1
        when 1
          lftq - 1
        else
          (lftq.inverse(lftp) * lftq - 1) / lftp
        end
      end

      # Returns left end of first free child interval.
      def next_child_lft
        lftp, lftq = self.lftp + self.rgtp, self.lftq + self.rgtq
        children.find(:all, :order => %(lftp, lftq)).each do |child|
          break if lftp != child.lftp
          lftp += self.lftp
          lftq += self.lftq
        end
        return lftp, lftq
      end
    end
  end
end

ActiveRecord::Base.send :include, ActiveRecord::Acts::NestedInterval
