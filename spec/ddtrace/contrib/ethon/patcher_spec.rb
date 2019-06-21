require 'spec_helper'
require 'ddtrace'
require 'typhoeus'

RSpec.describe Datadog::Contrib::Typhoeus::Patcher do
  describe '.patch' do
    it 'adds RequestPatch to ancestors of Request class' do
      described_class.patch

      expect(Typhoeus::Request.ancestors).to include(Datadog::Contrib::Typhoeus::RequestPatch)
    end
  end
end
