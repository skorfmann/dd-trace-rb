require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/typhoeus/configuration/settings'
require 'ddtrace/contrib/typhoeus/patcher'

module Datadog
  module Contrib
    module Typhoeus
      # Description of Typhoeus integration
      class Integration
        include Contrib::Integration
        register_as :typhoeus

        def self.version
          Gem.loaded_specs['typhoeus'] && Gem.loaded_specs['typhoeus'].version
        end

        def self.present?
          super && defined?(::Typhoeus::Request)
        end

        def self.compatible?
          super && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('1.9.3')
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
