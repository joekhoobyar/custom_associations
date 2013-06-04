require 'active_record'
require 'active_record/base'
require 'active_support/concern'
require 'custom_associations/version'

module CustomAssociations
  
  # Builders for the DSL.
  module Builder
    
    class CustomizableAssociation < ActiveRecord::Associations::Builder::Association
      self.valid_options -= [ :foreign_key, :validate ]
      self.valid_options += [ :as, :table_name, :joins, :order, :group, :having, :limit, :offset, :inverse_of ]

    private
    
      # Ensure that the association is readonly.
      def define_writers
        mixin.remove_possible_method("#{name}=")
      end
    end
    
    class HasOneCustom < CustomizableAssociation 
      self.macro = :has_one_custom
    end
    
    class HasManyCustom < CustomizableAssociation
      self.macro = :has_many_custom
      
      self.valid_options += [  :finder_sql, :counter_sql ]
        
	    attr_reader :block_extension

	    def self.build(model, name, options, &extension)
	      new(model, name, options, &extension).build
	    end
	
	    def initialize(model, name, options, &extension)
	      super(model, name, options)
	      @block_extension = extension
	    end
	
	    def build
	      wrap_block_extension
	      super
	    end
	    
	  private

      def wrap_block_extension
        options[:extend] = Array.wrap(options[:extend])

        if block_extension
          silence_warnings do
            model.parent.const_set(extension_module_name, Module.new(&block_extension))
          end
          options[:extend].push("#{model.parent}::#{extension_module_name}".constantize)
        end
      end

      def extension_module_name
        @extension_module_name ||= "#{model.to_s.demodulize}#{name.to_s.camelize}AssociationExtension"
      end

      def define_readers
        super

        name = self.name
        mixin.redefine_method("#{name.to_s.singularize}_ids") do
          association(name).ids_reader
        end
      end
    end
  end

  # Customizable associations
  module Associations

#    # Extensions for the preloader strategy for eager-loading associated records.    
#    module Preloader
#      extend ActiveSupport::Concern
#      
#      included do
#        alias_method_chain :preloader_for, :custom
#      end
#
#      class HasOneCustom < ActiveRecord::Associations::Preloader::HasOne
#        
#        # Overridden to includes any specified joins.
#        def build_scope
#          super.joins(preload_options[:joins] || options[:joins])
#        end
#      end
#      
#      class HasManyCustom < ActiveRecord::Associations::Preloader::HasMany
#        
#        # Overridden to includes any specified joins.
#        def build_scope
#          super.joins(preload_options[:joins] || options[:joins])
#        end
#      end
#      
#    private
#    		  
#      def preloader_for_with_custom(reflection)
#        case reflection.macro
#        when :has_many_custom
#          HasManyCustom
#        when :has_one_custom
#          HasOneCustom
#        else
#          preloader_for_without_custom(reflection)
#        end
#      end
#    end
      
    module JoinAssociation
      extend ActiveSupport::Concern
		  
      included do
        alias_method_chain :build_constraint, :custom
        alias_method_chain :join_to, :custom
      end

		  # HACK: Dummy constraint node for integrating custom associations with ActiveRecord.
	    DummyConstraint = Object.new.tap{|o| def o.and(conditions) conditions end }.freeze

      # Overridden to support custom associations.
	    def build_constraint_with_custom(reflection, table, key, foreign_table, foreign_key)
        case reflection.source_macro
        when :has_one_custom, :has_many_custom
		      return DummyConstraint unless reflection.klass.finder_needs_type_condition?
		      reflection.klass.send(:type_condition, table)
        else
          build_constraint_without_custom(reflection, table, key, foreign_table, foreign_key)
        end
	    end
	    
      # Overridden to support custom associations.
      def join_to_with_custom(relation)
        case reflection.source_macro
        when :has_one_custom, :has_many_custom
          Array.wrap(reflection.options[:joins]).each do |join|
	          join = join.join(' ') if Array===join && join.all?{|j| j.is_a?(String)}
	          next if join.blank?
	          join = Arel.sql(join) if String===join
	          relation.join(join)
          end
        end
	      join_to_without_custom(relation)
      end

    end
    
    module JoinDependency
      extend ActiveSupport::Concern
      
      included do
        alias_method_chain :construct_association, :custom
      end

    protected
    
      # Overridden to support custom associations.
      def construct_association_with_custom(record, join_part, row)
        return if record.id.to_s != join_part.parent.record_id(row).to_s

        macro = join_part.reflection.macro
        if macro == :has_one_custom
          if record.association_cache.key?(join_part.reflection.name)
            association = record.association(join_part.reflection.name).target
          else
	          association = join_part.instantiate(row) unless row[join_part.aliased_primary_key].nil?
	          set_target_and_inverse(join_part, association, record)
	        end
        elsif macro == :has_many_custom
          association = join_part.instantiate(row) unless row[join_part.aliased_primary_key].nil?
          other = record.association(join_part.reflection.name)
          other.loaded!
          other.target.push(association) if association
          other.set_inverse_instance(association)
        else
          associaton = construct_association_without_custom(record, join_part, row)
        end
        association
      end
    end
    
    # Gutted to support associations without explicit keys.
    class CustomizableAssociationScope < ActiveRecord::Associations::AssociationScope
      
    private

      # Overridden to remove chain support.
      def add_constraints(scope)
        table, foreign_table = construct_tables

        if reflection.type
	        scope = scope.where(table[reflection.type].eq(owner.class.base_class.name))
        end
        
        conditions.first.each do |condition|
          scope = scope.where(interpolate(condition))
        end

        scope
      end
      
    end
    
    # Patterned after belongs_to and has_one associations in AR.
    class HasOneCustomAssociation < ActiveRecord::Associations::Association

      # Ensure that the association is readonly.
      begin undef_method :creation_attributes, :set_owner_attributes, :build_record
      rescue NameError
      end
      
      # Copied from ActiveRecord::Associations::SingularAssociation
      def reader(force_reload = false)
        if force_reload
          klass.uncached { reload }
        elsif !loaded? || stale_target?
          reload
        end

        target
      end
      
      # Overridden to use CustomAssociationScope.
      def association_scope
        @association_scope ||= CustomizableAssociationScope.new(self).scope if klass
      end
      
    private

      def find_target
        scoped.first.tap { |record| set_inverse_instance(record) }
      end

    end

  end
  
  # Reflection for custom associations.
	class Reflection < ActiveRecord::Reflection::AssociationReflection
	  def initialize(macro, name, options, active_record)
	    super
	    @collection = (macro==:has_many_custom)
	  end
	      
	  def association_class
	    case macro
	    when :has_one_custom
	      Associations::HasOneCustomAssociation
	    when :has_many_custom
	      Associations::HasManyCustomAssociation
	    end
	  end
	end
	
	# Relation extensions to disable preloading for custom associations.
	module Relation
	  extend ActiveSupport::Concern
		  
	  included do
	    alias_method_chain :eager_loading?, :custom
	  end
	  
    def eager_loading_with_custom?
      @should_eager_load ||= eager_loading_without_custom? || ! supports_preloading?
    end

	private
	
	  # Checks if this relation supports preloading (which is disabled for custom associations)
	  def supports_preloading?(klass=@klass, includes=@includes_values)
	    includes.all? do |(a,b)|
	      a = klass.reflections[a.to_sym]
	      a && ! a.is_a?(Reflection) && (! b.present? || supports_preloading?(a.klass, Array.wrap(b)))
	    end
	  end
	end
  
  module Core
	  extend ActiveSupport::Concern

	  module ClassMethods
	    # DSL method
	    def has_one_custom(name, options = {}, &extension)
	      Builder::HasOneCustom.build(self, name, options, &extension)
	    end
	    
	    # DSL method
	    def has_many_custom(name, options = {}, &extension)
	      Builder::HasManyCustom.build(self, name, options, &extension)
	    end
	
	    # Overridden to create reflections for custom associations.
	    def create_reflection(macro, name, options, active_record)
	      case macro
	      when :has_one_custom, :has_many_custom
	        reflection = CustomAssociations::Reflection.new(macro, name, options, active_record)
	        self.reflections = self.reflections.merge(name => reflection)
	        reflection
	      else
	        super
	      end
	    end
	  end
  end
  
  # Installs this extension into ActiveRecord.
  def self.initialize!
    ::ActiveRecord::Base.send :include, Core
    ::ActiveRecord::Relation.send :include, Relation
    #::ActiveRecord::Associations::Preloader.send :include, Associations::Preloader
    ::ActiveRecord::Associations::JoinDependency.send :include, Associations::JoinDependency
    ::ActiveRecord::Associations::JoinDependency::JoinAssociation.send :include, Associations::JoinAssociation
  end
end

ActiveSupport.on_load(:active_record) do
  CustomAssociations.initialize!
end
