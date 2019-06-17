module Datadog
  module Contrib
    module Typhoeus
      # Typhoeus integration constants
      module Ext
        APP = 'typhoeus'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_REST_CLIENT_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_REST_CLIENT_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'typhoeus'.freeze
        SPAN_REQUEST = 'typhoeus.request'.freeze
      end
    end
  end
end
