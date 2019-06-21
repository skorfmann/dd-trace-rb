require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/ethon/ext'

module Datadog
  module Contrib
    module Ethon
      # Ethon MultiPatch
      module MultiPatch
        def self.included(base)
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            base.class_eval do
              alias_method :add_without_datadog, :add
              remove_method :add

              include InstanceMethods
            end
          else
            base.send(:prepend, InstanceMethods)
          end
        end

        # Compatibility shim for Rubies not supporting `.prepend`
        module InstanceMethodsCompatibility
          def add(easy)
            add_without_datadog(easy)
          end
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          include InstanceMethodsCompatibility unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')

          def add(easy)
            handles = super(easy)
            if handles.nil? || !tracer_enabled?
              return handles
            end

            easy.datadog_before_request
            handles
          end

          private

          def datadog_configuration
            Datadog.configuration[:ethon]
          end

          def tracer_enabled?
            datadog_configuration[:tracer].enabled
          end
        end
      end
    end
  end
end
