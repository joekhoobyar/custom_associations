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
    
    module CustomizablePreloader
      extend ActiveSupport::Concern
		  
      def preloader_for(reflection)
        case reflection.macro
        when :has_many_custom
          HasMany
        when :has_one_custom
          HasOne
        else
          super
        end
      end
    end
      
    module CustomizableJoinAssociation
      extend ActiveSupport::Concern
		  
		  # HACK: Dummy constraint node for integrating custom associations with ActiveRecord.
		  DummyConstraint = Object.new.tap{|o| def o.and(conditions) conditions end }.freeze

      # Overridden to support custom associations.
	    def build_constraint(reflection, table, key, foreign_table, foreign_key)
        case reflection.source_macro
        when :has_one_custom, :has_many_custom
		      if reflection.klass.finder_needs_type_condition?
		        reflection.klass.send(:type_condition, table)
		      else
            CustomAssociations::DummyConstraint.new
		      end
        else
          super
        end
	    end
    end
    
    module CustomizableJoinDependency
      extend ActiveSupport::Concern
      
    protected
    
      # Overridden to support custom associations.
      def construct_association(record, join_part, row)
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
          associaton = super
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
    ::ActiveRecord::Associations::Preloader.send :include, Associations::CustomizablePreloader
    ::ActiveRecord::Associations::JoinDependency.send :include, Associations::CustomizableJoinDependency
    ::ActiveRecord::Associations::JoinDependency::JoinAssociation.send :include, Associations::CustomizableJoinAssociation
  end
end

ActiveSupport.on_load(:active_record) do
  CustomAssociations.initialize!
end