# frozen_string_literal: true

require_relative "./error"

require "service_skeleton/config_variable"

class ServiceSkeleton
  module ConfigVariables
    attr_reader :registered_variables

    UNDEFINED = Class.new
    private_constant :UNDEFINED

    def register_variable(name, **opts, &callback)
      @registered_variables ||= []

      @registered_variables << ServiceSkeleton::ConfigVariable.new(name, **opts, &callback)
    end

    def string(var_name, default: UNDEFINED, sensitive: false)
      register_variable(var_name, sensitive: sensitive) do |value|
        maybe_default(value, default, var_name) do
          value
        end
      end
    end

    def boolean(var_name, default: UNDEFINED, sensitive: false)
      register_variable(var_name, sensitive: sensitive) do |value|
        maybe_default(value, default, var_name) do
          case value
          when /\A(no|n|off|0|false)\z/i
            false
          when /\A(yes|y|on|1|true)\z/i
            true
          else
            raise ServiceSkeleton::Error::InvalidEnvironmentError,
                  "Value #{value.inspect} for environment variable #{var_name} is not a valid boolean value"
          end
        end
      end
    end

    def integer(var_name, default: UNDEFINED, sensitive: false, range: -Float::INFINITY..Float::INFINITY)
      register_variable(var_name, sensitive: sensitive) do |value|
        maybe_default(value, default, var_name) do
          if value =~ /\A-?\d+\z/
            value.to_i.tap do |i|
              unless range.include?(i)
                raise ServiceSkeleton::Error::InvalidEnvironmentError,
                  "Value #{i} for environment variable #{var_name} is out of the valid range (must be between #{range.first} and #{range.last} inclusive)"
              end
            end
          else
            raise ServiceSkeleton::Error::InvalidEnvironmentError,
                  "Value #{value.inspect} for environment variable #{var_name} is not a valid integer value"
          end
        end
      end
    end

    def float(var_name, default: UNDEFINED, sensitive: false, range: -Float::INFINITY..Float::INFINITY)
      register_variable(var_name, sensitive: sensitive) do |value|
        maybe_default(value, default, var_name) do
          if value =~ /\A-?\d+.?\d*\z/
            value.to_f.tap do |i|
              unless range.include?(i)
                raise ServiceSkeleton::Error::InvalidEnvironmentError,
                  "Value #{i} for environment variable #{var_name} is out of the valid range (must be between #{range.first} and #{range.last} inclusive)"
              end
            end
          else
            raise ServiceSkeleton::Error::InvalidEnvironmentError,
                  "Value #{value.inspect} for environment variable #{var_name} is not a valid numeric value"
          end
        end
      end
    end

    def path_list(var_name, default: UNDEFINED, sensitive: false)
      register_variable(var_name, sensitive: sensitive) do |value|
        maybe_default(value, default, var_name) do
          value.split(":")
        end
      end
    end

    def kv_list(var_name, default: UNDEFINED, sensitive: false, key_pattern: nil)
      key_pattern ||= /\A#{var_name}_(.*)\z/
      register_variable(var_name, sensitive: sensitive, key_pattern: key_pattern) do |matches|
        maybe_default(matches, default, var_name) do
          matches.transform_keys do |k|
            key_pattern.match(k)[1].to_sym
          end
        end
      end
    end

    private

    def maybe_default(value, default, var_name)
      if value.nil? || value == {}
        if default == UNDEFINED
          raise ServiceSkeleton::Error::InvalidEnvironmentError,
                "Value for required environment variable #{var_name} not specified"
        else
          default
        end
      else
        yield
      end
    end
  end
end
