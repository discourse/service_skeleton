# frozen_string_literal: true

require_relative "./error"

require "service_skeleton/config_variable"

class ServiceSkeleton
  module ConfigVariables
    attr_reader :registered_variables

    UNDEFINED = Module.new
    private_constant :UNDEFINED

    def register_variable(name, klass, **opts)
      @registered_variables ||= []

      if opts[:default] == UNDEFINED
        opts.delete(:default)
      end

      @registered_variables << {
        name: name,
        class: klass,
        opts: opts,
      }
    end

    def string(var_name, default: UNDEFINED, sensitive: false)
      register_variable(var_name, ConfigVariable::String, default: default, sensitive: sensitive)
    end

    def boolean(var_name, default: UNDEFINED, sensitive: false)
      register_variable(var_name, ConfigVariable::Boolean, default: default, sensitive: sensitive)
    end

    def integer(var_name, default: UNDEFINED, sensitive: false, range: -Float::INFINITY..Float::INFINITY)
      register_variable(var_name, ConfigVariable::Integer, default: default, sensitive: sensitive, range: range)
    end

    def float(var_name, default: UNDEFINED, sensitive: false, range: -Float::INFINITY..Float::INFINITY)
      register_variable(var_name, ConfigVariable::Float, default: default, sensitive: sensitive, range: range)
    end

    def path_list(var_name, default: UNDEFINED, sensitive: false)
      register_variable(var_name, ConfigVariable::PathList, default: default, sensitive: sensitive)
    end

    def kv_list(var_name, default: UNDEFINED, sensitive: false, key_pattern: /\A#{var_name}_(.*)\z/)
      register_variable(var_name, ConfigVariable::KVList, default: default, sensitive: sensitive, key_pattern: key_pattern)
    end

    def enum(var_name, values:, default: UNDEFINED, sensitive: false)
      unless values.is_a?(Hash) || values.is_a?(Array)
        raise ArgumentError,
              "values option to enum must be a hash or array"
      end

      register_variable(var_name, ConfigVariable::Enum, default: default, sensitive: sensitive, values: values)
    end
  end
end

require_relative "config_variable/string"
require_relative "config_variable/boolean"
require_relative "config_variable/integer"
require_relative "config_variable/float"
require_relative "config_variable/path_list"
require_relative "config_variable/kv_list"
require_relative "config_variable/enum"
