module Datadog
  module Contrib
    module Ethon
      # Patcher enables patching of 'ethon' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:ethon)
        end

        def patch
          do_once(:ethon) do
            require 'ddtrace/ext/app_types'
            require 'ddtrace/contrib/ethon/easy_patch'


            ::Ethon::Easy.send(:include, EasyPatch)
          end
        end
      end
    end
  end
end
