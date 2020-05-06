require 'socket'
require 'time'
require 'uri'
require 'stringio'
require 'rack'
require_relative 'const'
require_relative 'logger'
require_relative 'static_file'

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
    include Fawn::Logger
    include Fawn::Const

    RACK_CONFIG = 'config.ru'.freeze
    def build_app(app = nil)
      ::Rack::Builder.parse_file(RACK_CONFIG).first
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
        #{body.join}
      TEXT
    end

    def handle_request(sock)
      rack_env = parse_rack_env(*read_content(sock))
      logger.info rack_env
      raise UnsupportedRequestError unless ['HEAD', 'GET'].include?(rack_env[REQUEST_METHOD])
      response = make_response(*@app.call(rack_env))
      logger.info response
      sock.write response
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
          raise e
        end
      end
    end
  end
end