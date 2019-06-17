require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/typhoeus/ext'

module Datadog
  module Contrib
    module Typhoeus
      # Typhoeus RequestPatch
      module RequestPatch
        def self.included(base)
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            base.class_eval do
              alias_method :execute_without_datadog, :execute
              remove_method :execute
              include InstanceMethods
            end
          else
            base.send(:prepend, InstanceMethods)
          end
        end

        # Compatibility shim for Rubies not supporting `.prepend`
        module InstanceMethodsCompatibility
          def execute(&block)
            execute_without_datadog(&block)
          end
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          include InstanceMethodsCompatibility unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')

          def run
            if !datadog_configuration[:tracer].enabled
              return super()
            end

            uri = URI.parse(url)
            datadog_trace_request(uri) do |span|
              if datadog_configuration[:distributed_tracing]
                options[:headers] ||= {}
                Datadog::HTTPPropagator.inject!(span.context, options[:headers])
              end

              super()
            end
          end

          def datadog_tag_request(uri, span)
            span.resource = options.fetch(:method, :get).to_s.upcase

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, options.fetch(:method, :get).to_s.upcase)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
          end

          def datadog_trace_request(uri)
            span = datadog_configuration[:tracer].trace(Ext::SPAN_REQUEST,
                                                        service: datadog_configuration[:service_name],
                                                        span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND)

            datadog_tag_request(uri, span)

            yield(span).tap do |response|
              # Verify return value is a response
              # If so, add additional tags.
              if response.is_a?(::Typhoeus::Response)
                if response.timed_out?
                  set_span_error_message(span, 'Request has timed out')
                elsif response.code == 0
                  set_span_error_message(span, "Request has failed: #{response.return_message}")
                else
                  span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.code)
                  if Datadog::Ext::HTTP::ERROR_RANGE.cover?(response.code)
                    set_span_error_message(span,
                      "Request has failed with HTTP error: #{response.code} (#{response.return_message})")
                  end
                end
              end
            end
          rescue Exception => e
            # rubocop:enable Lint/RescueException
            span.set_error(e)

            raise e
          ensure
            span.finish
          end

          private

          def set_span_error_message(span, message)
            # Sets span error from message, in case there is no exception available
            span.status = Datadog::Ext::Errors::STATUS
            span.set_tag(Datadog::Ext::Errors::MSG, message)
          end

          def datadog_configuration
            Datadog.configuration[:typhoeus]
          end

          def analytics_enabled?
            Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end
        end
      end
    end
  end
end
