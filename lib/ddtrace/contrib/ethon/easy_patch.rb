require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/ethon/ext'

module Datadog
  module Contrib
    module Ethon
      # Ethon EasyPatch
      module EasyPatch
        def self.included(base)
          if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
            base.class_eval do
              [:http_request, :set_attributes, :perform, :complete].each do |method|
                alias_method "#{method.to_s}_without_datadog".to_sym, method
                remove_method method
              end

              alias_method :headers_set_without_datadog, :headers=
              remove_method :headers=

              include InstanceMethods
            end
          else
            base.send(:prepend, InstanceMethods)
          end
        end

        # Compatibility shim for Rubies not supporting `.prepend`
        module InstanceMethodsCompatibility
          def http_request(url, action_name, options = {})
            http_request_without_datadog(url, action_name, options)
          end

          def set_attributes(options)
            set_attributes_without_datadog(options)
          end

          def headers=(headers)
            headers_set_without_datadog(headers)
          end

          def perform
            perform_without_datadog
          end

          def complete
            complete_without_datadog
          end
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          include InstanceMethodsCompatibility unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')

          def http_request(url, action_name, options = {})
            return super unless tracer_enabled?

            # It's tricky to get HTTP method from libcurl
            @datadog_method = action_name.to_s.upcase
            super
          end

          def set_attributes(options)
            return super unless tracer_enabled?

            # Make sure headers= will get called
            options[:headers] ||= {}
            super options
          end

          def headers=(headers)
            return super unless tracer_enabled?

            # Store headers to call this method again when span is ready
            headers ||= {}
            @datadog_original_headers = headers
            super headers
          end

          def perform
            return super unless tracer_enabled?
            datadog_before_request
            super
          end

          def complete
            return super unless tracer_enabled?

            begin
              response_options = mirror.options
              response_code = (response_options[:response_code] || response_options[:code]).to_i
              return_code = response_options[:return_code]
              if return_code == :operation_timedout
                set_span_error_message("Request has timed out")
              elsif response_code == 0
                message = return_code ? Ethon::Curl.easy_strerror(return_code) : "unknown reason"
                set_span_error_message("Request has failed: #{message}")
              else
                @datadog_span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response_code)
                if Datadog::Ext::HTTP::ERROR_RANGE.cover?(response_code)
                  set_span_error_message("Request has failed with HTTP error: #{response_code}")
                end
              end
            ensure
              @datadog_span.finish
              @datadog_span = nil
            end
            super
          end

          def datadog_before_request
            datadog_start_span

            if datadog_configuration[:distributed_tracing]
              Datadog::HTTPPropagator.inject!(@datadog_span.context, @datadog_original_headers)
              self.headers = @datadog_original_headers
            end
          end

          def datadog_start_span
            @datadog_span = datadog_configuration[:tracer].trace(Ext::SPAN_REQUEST,
              service: datadog_configuration[:service_name],
              span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND)

            datadog_tag_request
          end

          def datadog_tag_request
            span = @datadog_span
            uri = URI.parse(url)
            method = @datadog_method ? '#{@datadog_method} ' : ''
            span.resource = "#{method}#{uri.path}"

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            span.set_tag(Datadog::Ext::HTTP::URL, uri.path)
            span.set_tag(Datadog::Ext::HTTP::METHOD, method)
            span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
            span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port)
          end

          private

          def set_span_error_message(message)
            # Sets span error from message, in case there is no exception available
            @datadog_span.status = Datadog::Ext::Errors::STATUS
            @datadog_span.set_tag(Datadog::Ext::Errors::MSG, message)
          end

          def datadog_configuration
            Datadog.configuration[:ethon]
          end

          def tracer_enabled?
            datadog_configuration[:tracer].enabled
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
