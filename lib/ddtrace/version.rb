module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 27
    PATCH = 0
    PRE = 'pre'

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')
  end
end
