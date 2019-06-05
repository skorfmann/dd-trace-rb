require 'spec_helper'

require 'ddtrace/transport/http'

RSpec.describe Datadog::Transport::HTTP do
  describe '#default' do
    subject(:client) { described_class.default(&options_block) }
    let(:options_block) { proc { |_transport| } }
    it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Client) }
  end
end
