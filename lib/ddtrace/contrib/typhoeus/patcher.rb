module Datadog
  module Contrib
    module Typhoeus
      # Patcher enables patching of 'typhoeus' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:typhoeus)
        end

        def patch
          do_once(:typhoeus) do
            require 'ddtrace/ext/app_types'
            require 'ddtrace/contrib/typhoeus/request_patch'


            ::Ethon::Easy.send(:include, RequestPatch)
            #::Typhoeus::Request.send(:include, RequestPatch)
          end
        end
      end
    end
  end
end
