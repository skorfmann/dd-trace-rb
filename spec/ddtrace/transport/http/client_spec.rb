require 'spec_helper'

require 'ddtrace/transport/http'
require 'ddtrace/transport/http/client'

RSpec.describe Datadog::Transport::HTTP::Client do
  # TODO: Make this easier to initialize?
  subject(:client) { described_class.new(apis, active_api) }
  let(:apis) { instance_double(Datadog::Transport::HTTP::API::Map) }
  let(:active_api) { double('active_api') }

  context 'default' do
    subject(:client) { Datadog::Transport::HTTP.default(&options_block) }
    let(:options_block) { proc { |_transport| } }

    describe '#deliver' do
      subject(:response) { client.deliver(request) }
      let(:request) { Datadog::Transport::Request.new(:traces, parcel) }
      let(:parcel) { Datadog::Transport::Traces::Parcel.new(get_test_traces(2)) }

      context 'to the default adapter' do
        it { expect(response.ok?).to be true }
      end

      context 'to the test adapter' do
        let(:options_block) { proc { |t| t.adapter :test } }
        it { expect(response.ok?).to be true }
      end
    end
  end

  describe '#deliver' do
    subject(:response) { client.deliver(request) }
  end
end
