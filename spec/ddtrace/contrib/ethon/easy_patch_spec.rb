require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'ddtrace'
require 'ddtrace/contrib/ethon/easy_patch'
require 'typhoeus'
require 'stringio'
require 'webrick'


RSpec.describe Datadog::Contrib::Ethon::EasyPatch do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  before(:all) do
    @port = 6220

    @log_buffer = $stderr #StringIO.new
    log = WEBrick::Log.new(@log_buffer, WEBrick::Log::DEBUG)
    access_log = [[@log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]]

    server = WEBrick::HTTPServer.new(Port: @port, Logger: log, AccessLog: access_log, RequestTimeout: 0.5)
    server.mount_proc'/'  do |req, res|
      if req.query["timeout"]
        sleep(1)
      end
      res.status = (req.query["status"] || req.body["status"]).to_i
      if req.query["return_headers"]
        headers = {}
        req.each do |header_name|
          headers[header_name] = req.header[header_name]
        end
        res.body = JSON.generate({headers: headers})
      else
        res.body = "response"
      end
    end
    Thread.new { server.start }
    @server = server
  end
  after(:all) { @server.shutdown }

  let(:host) { 'localhost' }
  let(:status) { '200' }
  let(:path) { '/sample/path' }
  let(:method) { 'GET' }
  let(:timeout) { false }
  let(:return_headers) { false }
  let(:url) {
    url = "http://#{host}:#{@port}#{path}?"
    url += "status=#{status}&" if status
    url += "return_headers=true&" if return_headers
    url += "timeout=true" if timeout
    url
  }


  before do
    Datadog.configure do |c|
      c.use :ethon, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:ethon].reset_configuration!
    example.run
    Datadog.registry[:ethon].reset_configuration!
  end

  describe 'instrumented request' do
    subject(:request) { Typhoeus::Request.new(url, timeout: 0.5).run }

    shared_examples_for 'span' do
      it 'has tag with target host' do
        expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
      end

      it 'has tag with target port' do
        expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(@port.to_s)
      end

      it 'has tag with method' do
        expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq(method)
      end

      it 'has tag with URL' do
        expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
      end

      it 'has tag with status code' do
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status)
      end

      it 'is http type' do
        expect(span.span_type).to eq('http')
      end

      it 'is named correctly' do
        expect(span.name).to eq('ethon.request')
      end

      it 'has correct service name' do
        expect(span.service).to eq('ethon')
      end
    end

    shared_examples_for 'instrumented request' do
      it 'creates a span' do
        expect { request }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
      end

      it 'returns response' do
        expect(request.body).to eq("response")
      end

      describe 'created span' do
        subject(:span) { tracer.writer.spans.first }

        context 'response is successfull' do
          before { request }

          it_behaves_like 'span'

          # it_behaves_like 'analytics for integration' do
          #    let(:analytics_enabled_var) { Datadog::Contrib::Ethon::Ext::ENV_ANALYTICS_ENABLED }
          #    let(:analytics_sample_rate_var) { Datadog::Contrib::Ethon::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          # end
        end

        context 'response has internal server error status' do
          let(:status) { 500 }

          before { request }

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          it 'has error set' do
            expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('Request has failed with HTTP error: 500')
          end
          it 'has no error stack' do
            expect(span.get_tag(Datadog::Ext::Errors::STACK)).to be_nil
          end
          it 'has no error type' do
            expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to be_nil
          end
        end

        context 'response has not found status' do
          let(:status) { 404 }

          before { request }

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          it 'has no error set' do
            expect(span.get_tag(Datadog::Ext::Errors::MSG)).to be_nil
          end
        end

        context 'request timed out' do
          let(:timeout) { true }

          before { request }

          it 'has no status code set' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to be_nil
          end

          it 'has error set' do
            expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('Request has failed: Timeout was reached')
          end
        end
      end
    end

    it_behaves_like 'instrumented request'

    context 'distributed tracing default' do
      it_behaves_like 'instrumented request'

      shared_examples_for 'propagating distributed headers' do
        let(:return_headers) { true }
        let(:span) { tracer.writer.spans.first }

        it 'propagates the headers' do
          response = request
          headers = JSON.parse(response.body)["headers"]
          distributed_tracing_headers = { 'x-datadog-parent-id' => [span.span_id.to_s],
            'x-datadog-trace-id' => [span.trace_id.to_s] }

          expect(headers).to include(distributed_tracing_headers)
        end
      end

      it_behaves_like 'propagating distributed headers'

      context 'with sampling priority' do
        let(:return_headers) { true }
        let(:sampling_priority) { 0.2 }

        before do
          tracer.provider.context.sampling_priority = sampling_priority
        end

        it_behaves_like 'propagating distributed headers'

        it 'propagates sampling priority' do
          response = request
          headers = JSON.parse(response.body)["headers"]

          expect(headers).to include({ 'x-datadog-sampling-priority' => [sampling_priority.to_s] })
        end
      end
    end

    context 'distributed tracing disabled' do
      let(:configuration_options) { super().merge(distributed_tracing: false) }

      it_behaves_like 'instrumented request'

      shared_examples_for 'does not propagate distributed headers' do
        let(:return_headers) { true }

        it 'does not propagate the headers' do
          response = request
          headers = JSON.parse(response.body)["headers"]

          expect(headers).not_to include('x-datadog-parent-id', 'x-datadog-trace-id')
        end
      end

      it_behaves_like 'does not propagate distributed headers'

      context 'with sampling priority' do
        let(:return_headers) { true }
        let(:sampling_priority) { 0.2 }

        before do
          tracer.provider.context.sampling_priority = sampling_priority
        end

        it_behaves_like 'does not propagate distributed headers'

        it 'does not propagate sampling priority headers' do
          response = request
          headers = JSON.parse(response.body)["headers"]

          expect(headers).not_to include('x-datadog-sampling-priority')
        end
      end
    end
    # rdebug-ide --host 0.0.0.0 --port 1234 --dispatcher-port 26162 -- bundle exec appraisal contrib rake spec:ethon SPEC_OPTS="-e \"has no error set on post request span\""

    context 'with single Hydra request' do
      subject(:request) do
        hydra = Typhoeus::Hydra.new
        request = Typhoeus::Request.new(url, timeout: 0.5)
        hydra.queue(request)
        hydra.run
        request.response
      end

      it_behaves_like 'instrumented request'
    end

    context 'with concurrent Hydra requests' do
      let(:url_1) { "http://#{host}:#{@port}#{path}?status=200&timeout=true" }
      let(:url_2) { "http://#{host}:#{@port}#{path}" }
      let(:request_1) {Typhoeus::Request.new(url_1, timeout: 0.5)}
      let(:request_2) {Typhoeus::Request.new(url_2, method: :post, timeout: 0.5, body: {status: 404})}
      subject(:request) do
        hydra = Typhoeus::Hydra.new
        hydra.queue(request_1)
        hydra.queue(request_2)
        hydra.run
      end

      it 'creates 2 spans' do
        expect { request }.to change { tracer.writer.spans.count }.to 2
      end

      describe 'created spans' do
        subject(:spans) { tracer.writer.spans }
        let(:span_get) { spans.select { |span| span.get_tag(Datadog::Ext::HTTP::METHOD) == 'GET' }.first }
        let(:span_post) { spans.select { |span| span.get_tag(Datadog::Ext::HTTP::METHOD) == 'POST' }.first }

        before {
          Ethon.logger.level = Logger::DEBUG
          request
        }

        it_behaves_like 'span' do
          let(:span) { span_get }
          let(:status) { nil }
        end

        it_behaves_like 'span' do
          let(:span) { span_post }
          let(:status) { "404" }
          let(:method) { "POST" }
        end

        it 'has timeout set on get request span' do
          expect(span_get.get_tag(Datadog::Ext::Errors::MSG)).to eq('Request has failed: Timeout was reached')
        end
      end

    end

    context 'with Easy request' do

    end
  end
end
