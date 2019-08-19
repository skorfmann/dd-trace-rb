module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 25
    PATCH = 1
    PRE = 'ws100'.freeze

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')
  end
end
