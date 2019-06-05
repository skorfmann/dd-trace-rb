require 'ddtrace/transport/http/env'
require 'ddtrace/transport/http/compatibility'

module Datadog
  module Transport
    module HTTP
      # Routes, encodes, and sends tracer data to the trace agent via HTTP.
      class Client
        include Compatibility

        attr_reader \
          :apis,
          :active_api

        def initialize(apis, active_api)
          @apis = apis

          # Activate initial API
          raise UnknownApiVersion unless apis.key?(active_api)
          @active_api = apis[active_api]
        end

        def deliver(request)
          env = build_env(request)
          response = active_api.call(env)

          # If API should be downgraded, downgrade and try again.
          if downgrade?(response)
            downgrade!
            response = deliver(parcel)
          end

          response
        end

        def build_env(request)
          Env.new(request)
        end

        def downgrade?(response)
          return false if apis.fallback_from(active_api).nil?
          response.not_found? || response.unsupported?
        end

        def downgrade!
          @active_api = apis.fallback_from(active_api)
        end

        # Raised when configured with an unknown API version
        class UnknownApiVersion < StandardError
          attr_reader :version

          def initialize(version)
            @version = version
          end

          def message
            "No matching transport API for version #{version}!"
          end
        end
      end
    end
  end
end
