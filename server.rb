require 'socket'
require 'time'
require 'uri'
require 'stringio'
require_relative 'logger'

module Fawn
  CHUNK_SIZE = 512
  HTTP_1_1 = 'HTTP/1.1'.freeze
  CRLF = "\r\n".freeze
  BASE_DIR = './dist'.freeze
  MIME =
    {
      jpg: 'image/jpg',
      jpeg: 'image/jpg',
      ico: 'image/webp',
      png: 'image/png',
      gif: 'image/gif',
      html: 'text/html',
      css: 'text/css',
      js: 'application/js',
    }

  class Server
    class InvalidFormatError < StandardError; end
    class UnsupportedRequestError < StandardError; end

    module NonBlock
      def self.included(base)
        puts 'NonBlocking mode enabled'
      end
      def read_content(sock)
        String.new.then do |str|
          loop do
            str << (t = sock.recv_nonblock(CHUNK_SIZE))
            break str if t.size < CHUNK_SIZE
          rescue Errno::EAGAIN
            logger.warn "EAGAIN: #{e.full_message}"
            IO.select([sock])
          end
        end
      end
      def sock_accept(sock)
        sock.accept_nonblock
      end
    end

    module Block
      def read_content(sock)
        String.new.then do |str|
          loop do
            str << (t = sock.recv(CHUNK_SIZE))
            break str if t.size < CHUNK_SIZE
          end
        end
      end
      def sock_accept(sock)
        sock.accept
      end
    end

    BLOCK_MODE = Block

    include BLOCK_MODE

    class StaticFile
      def initialize(app)
        @app = app
      end
      def call(env)
        headers = {}
        response =
          if File.readable?(filename = "#{BASE_DIR}#{env[SCRIPT_NAME]}") && File.file?(filename)
            {
              status: 200,
              body: (body = File.read(filename)),
              content_type: "#{MIME[filename.split(".").last.to_sym] || 'application/octet-stream'}; charset=#{body.encoding}"
            }
          else
            {
              status: 404,
              body: 'File not found',
              content_type: 'text/plain; charset=utf-8',
            }
          end
        headers['Content-Type'] = response[:content_type]
        headers['Date'] = DateTime.now.rfc822
        headers['Content-Length'] = (body = response[:body]).bytesize
        [response[:status], headers, body]
      end
    end

    def build_app(app = nil)
      require 'bundler/setup'
      Bundler.require(:default)
      [StaticFile, Rack::Runtime].inject(app) do |app, klass|
        klass.new(app)
      end
    end

    def initialize(**opts)
      @multithread = opts[:multithread]
      @app = build_app(opts[:app])
    end

    def parse_headers(str)
      lines = str.lines # TODO: body がバイナリのときも考える
      status = lines.shift
      index = lines.find_index {|line| line === CRLF }
      raise InvalidFormatError if index.nil?
      header_lines, request_body = lines[0...index], lines[(index+1)..-1].join
      http_headers = header_lines.map do |line|
        line.match(/(.*?):(.+)\r\n/).captures
      end.map {|key, value| ["HTTP_#{key.upcase}", value]}.to_h
      [[:method, :uri, :protocol].zip(status.split(" ")).to_h, http_headers, request_body]
    end
    

    REQUEST_METHOD    = 'REQUEST_METHOD'.freeze
    SCRIPT_NAME       = 'SCRIPT_NAME'.freeze
    PATH_INFO         = 'PATH_INFO'.freeze
    QUERY_STRING      = 'QUERY_STRING'.freeze
    SERVER_NAME       = 'SERVER_NAME'.freeze
    SERVER_PORT       = 'SERVER_PORT'.freeze
    RACK_VERSION      = 'rack.version'.freeze
    RACK_URL_SCHEME   = 'rack.url_scheme'.freeze
    RACK_INPUT        = 'rack.input'.freeze
    RACK_ERRORS       = 'rack.errors'.freeze
    RACK_MULTITHREAD  = 'rack.multithread'.freeze
    RACK_MULTIPROCESS = 'rack.multiprocess'.freeze
    RACK_RUN_ONCE     = 'rack.run_once'.freeze
    RACK_HIJACK_P     = 'rack.hijack?'.freeze
    RACK_HIJACK       = 'rack.hijack'.freeze
    RACK_HIJACK_IO    = 'rack.hijack_io'.freeze

    def parse_rack_env(str)
      metainfo, http_headers, request_body = parse_headers(str)
      raise UnsupportedRequestError unless metainfo[:protocol] === HTTP_1_1
      uri = URI.parse(metainfo[:uri])
      host, port = http_headers['HTTP_HOST']&.split(":")
      port ||= 80
      host ||= fail # TODO
      {
       REQUEST_METHOD    => metainfo[:method],
       SCRIPT_NAME       => uri.path,
       PATH_INFO         => '', # TODO
       QUERY_STRING      => uri.query,
       SERVER_NAME       => host,
       SERVER_PORT       => port,
       RACK_VERSION      => '1.3',
       RACK_URL_SCHEME   => 'http',
       RACK_INPUT        => StringIO.new(request_body),
       RACK_ERRORS       => $stderr,
       RACK_MULTITHREAD  => @multithread,
       RACK_MULTIPROCESS => false,
       RACK_RUN_ONCE     => false,
       RACK_HIJACK_P     => true,
       RACK_HIJACK       => proc {
         raise NotImplementedError, "only partial hijack is supported." },
       RACK_HIJACK_IO    => nil
      }.merge!(http_headers)
    end

    def make_response(status, headers, body)
      headers_text = headers.to_a.map {|k, v| "#{k}: #{v}"}.join(CRLF)
      <<~TEXT.chomp!
        #{HTTP_1_1} #{status}\r
        #{headers_text}\r
        \r
        #{body}
      TEXT
    end

    def handle_request(sock)
      rack_env = parse_rack_env(*read_content(sock))
      logger.info rack_env
      raise UnsupportedRequestError unless rack_env[REQUEST_METHOD] === 'GET'
      sock.write(make_response(*@app.call(rack_env)))
      sock.close
      logger.info "#{sock} is gone"
    end

    def run
      gs = TCPServer.open(ENV['LISTEN_HOST'] || '0.0.0.0', ENV['LISTEN_PORT'] || '8081')
      socks = [gs]
      puts 'server is on %s' % gs.addr.values_at(3, 1).join(':')

      while true
        nsock = IO.select(socks)
        next if nsock == nil
        nsock.first.each do |sock|
          if sock == gs
            socks.push(sock_accept(sock))
            logger.info "#{sock} is accepted"
          else
            yield sock
            socks.delete(sock)
          end
        rescue UnsupportedRequestError, InvalidFormatError => e
          logger.warn "#{e.full_message}"
          break
        end
      end
    end
  end
end

def test
  include Fawn
  server = Server.new
  server.run do |sock|
    server.handle_request(sock)
  end
end