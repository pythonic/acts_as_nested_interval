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

    module ClassMethods
      # The +options+ hash can include:
      # * <tt>:foreign_key</tt> -- the self-reference foreign key column name (default :parent_id).
      # * <tt>:scope_columns</tt> -- an array of columns to scope independent trees.
      # * <tt>:lft_index</tt> -- whether to use functional index for lft (default false).
      def acts_as_nested_interval(options = {})
        cattr_accessor :nested_interval_foreign_key
        cattr_accessor :nested_interval_scope_columns
        cattr_accessor :nested_interval_lft_index
        self.nested_interval_foreign_key = options[:foreign_key] || :parent_id
        self.nested_interval_scope_columns = Array(options[:scope_columns])
        self.nested_interval_lft_index = options[:lft_index]
        belongs_to :parent, :class_name => name, :foreign_key => nested_interval_foreign_key
        has_many :children, :class_name => name, :foreign_key => nested_interval_foreign_key, :dependent => :destroy
        named_scope :roots, :conditions => {nested_interval_foreign_key => nil}
        if columns_hash["rgt"]
          named_scope :preorder, :order => %(rgt DESC, lftp ASC)
        elsif columns_hash["rgtp"] && columns_hash["rgtq"]
          named_scope :preorder, :order => %(1.0 * rgtp / rgtq DESC, lftp ASC)
        else
          named_scope :preorder, :order => %(nested_interval_rgt(lftp, lftq) DESC, lftp ASC)
        end
        class_eval do
          include ActiveRecord::Acts::NestedInterval::InstanceMethods
          alias_method_chain :create, :nested_interval
          alias_method_chain :destroy, :nested_interval
          alias_method_chain :update, :nested_interval
          if columns_hash["lft"]
            def descendants
              quoted_table_name = self.class.quoted_table_name
              nested_interval_scope.scoped :conditions => %(#{lftp} < #{quoted_table_name}.lftp AND #{quoted_table_name}.lft BETWEEN #{1.0 * lftp / lftq} AND #{1.0 * rgtp / rgtq})
            end
          elsif nested_interval_lft_index
            def descendants
              quoted_table_name = self.class.quoted_table_name
              nested_interval_scope.scoped :conditions => %(#{lftp} < #{quoted_table_name}.lftp AND 1.0 * #{quoted_table_name}.lftp / #{quoted_table_name}.lftq BETWEEN #{1.0 * lftp / lftq} AND #{1.0 * rgtp / rgtq})
            end
          elsif connection.adapter_name == "MySQL"
            def descendants
              quoted_table_name = self.class.quoted_table_name
              nested_interval_scope.scoped :conditions => %((#{quoted_table_name}.lftp != #{rgtp} OR #{quoted_table_name}.lftq != #{rgtq}) AND #{quoted_table_name}.lftp BETWEEN 1 + #{quoted_table_name}.lftq * #{lftp} DIV #{lftq} AND #{quoted_table_name}.lftq * #{rgtp} DIV #{rgtq})
            end
          else
            def descendants
              quoted_table_name = self.class.quoted_table_name
              nested_interval_scope.scoped :conditions => %((#{quoted_table_name}.lftp != #{rgtp} OR #{quoted_table_name}.lftq != #{rgtq}) AND #{quoted_table_name}.lftp BETWEEN 1 + #{quoted_table_name}.lftq * CAST(#{lftp} AS BIGINT) / #{lftq} AND #{quoted_table_name}.lftq * CAST(#{rgtp} AS BIGINT) / #{rgtq})
            end
          end
        end
      end
    end

    module InstanceMethods
      def set_nested_interval(lftp, lftq)
        self.lftp, self.lftq = lftp, lftq
        self.rgtp = rgtp if has_attribute?(:rgtp)
        self.rgtq = rgtq if has_attribute?(:rgtq)
        self.lft = lft if has_attribute?(:lft)
        self.rgt = rgt if has_attribute?(:rgt)
      end

      # Creates record.
      def create_with_nested_interval
        if read_attribute(nested_interval_foreign_key).nil?
          set_nested_interval 0, 1
        else
          set_nested_interval *parent.lock!.next_child_lft
        end
        create_without_nested_interval
      end

      # Destroys record.
      def destroy_with_nested_interval
        lock! rescue nil
        destroy_without_nested_interval
      end

      def nested_interval_scope
        conditions = {}
        nested_interval_scope_columns.each do |column_name|
          conditions[column_name] = send(column_name)
        end
        self.class.scoped(:conditions => conditions)
      end

      # Updates record, updating descendants if parent association updated,
      # in which case caller should first acquire table lock.
      def update_with_nested_interval
        if read_attribute(nested_interval_foreign_key).nil?
          set_nested_interval 0, 1
        elsif !parent.updated?
          db_self = self.class.find(id, :lock => true)
          write_attribute(nested_interval_foreign_key, db_self.read_attribute(nested_interval_foreign_key))
          set_nested_interval db_self.lftp, db_self.lftq
        else
          # No locking in this case -- caller should have acquired table lock.
          db_self = self.class.find(id)
          db_parent = self.class.find(read_attribute(nested_interval_foreign_key))
          if db_parent.lftp == db_self.lftp && db_parent.lftq == db_self.lftq \
              || db_parent.lftp > db_parent.lftq * db_self.lftp / db_self.lftq \
              && db_parent.lftp <= db_parent.lftq * db_self.rgtp / db_self.rgtq \
              && (db_parent.lftp != db_self.rgtp || db_parent.lftq != db_self.rgtq)
            errors.add :parent_id, "is descendant"
            raise ActiveRecord::RecordInvalid, self
          end
          set_nested_interval *parent.next_child_lft
          mysql_tmp = "@" if connection.adapter_name == "MySQL"
          cpp = db_self.lftq * rgtp - db_self.rgtq * lftp
          cpq = db_self.rgtp * lftp - db_self.lftp * rgtp
          cqp = db_self.lftq * rgtq - db_self.rgtq * lftq
          cqq = db_self.rgtp * lftq - db_self.lftp * rgtq
          db_descendants = db_self.descendants
          if has_attribute?(:rgtp) && has_attribute?(:rgtq)
            db_descendants.update_all %(
              rgtp = #{cpp} * rgtp + #{cpq} * rgtq,
              rgtq = #{cqp} * #{mysql_tmp}rgtp + #{cqq} * rgtq
            ), mysql_tmp && %(@rgtp := rgtp)
            db_descendants.update_all %(rgt = 1.0 * rgtp / rgtq) if has_attribute?(:rgt)
          end
          db_descendants.update_all %(
            lftp = #{cpp} * lftp + #{cpq} * lftq,
            lftq = #{cqp} * #{mysql_tmp}lftp + #{cqq} * lftq
          ), mysql_tmp && %(@lftp := lftp)
          db_descendants.update_all %(lft = 1.0 * lftp / lftq) if has_attribute?(:lft)
        end
        update_without_nested_interval
      end

      def ancestors
        sqls = [%(NULL)]
        p, q = lftp, lftq
        while p != 0
          x = p.inverse(q)
          p, q = (x * p - 1) / q, x
          sqls << %(lftq = #{q} AND lftp = #{p})
        end
        nested_interval_scope.scoped :conditions => sqls * %( OR )
      end

      # Returns depth by counting ancestors up to 0 / 1.
      def depth
        n = 0
        p, q = lftp, lftq
        while p != 0
          x = p.inverse(q)
          p, q = (x * p - 1) / q, x
          n += 1
        end
        n
      end

      def lft
        1.0 * lftp / lftq
      end

      def rgt
        1.0 * rgtp / rgtq
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

      # Returns left end of interval for next child.
      def next_child_lft
        if child = children.find(:first, :order => %(lftq DESC))
          return lftp + child.lftp, lftq + child.lftq
        else
          return lftp + rgtp, lftq + rgtq
        end
      end
    end
  end
end

ActiveRecord::Base.send :include, ActiveRecord::Acts::NestedInterval
