require 'socket'
require 'time'
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
    class UnsupportedProtocolError < StandardError; end
    
    def read_content(sock)
      String.new.then do |str|
        loop do
          str << (t = sock.recv(CHUNK_SIZE))
          break str if t.size < CHUNK_SIZE
        end
      end
    end

    def read_content_nonblocking(sock)
      String.new.then do |str|
        loop do
          str << (t = sock.recv_nonblock(CHUNK_SIZE))
          break str if t.size < CHUNK_SIZE
        rescue Errno::EAGAIN
          IO.select([sock])
        end
      end
    end

    def parse_header(str)
      lines = str.lines # TODO: body がバイナリのときも考える
      status = lines.shift
      index = lines.find_index {|line| line === CRLF }
      raise InvalidFormatError if index.nil?
      header_lines, rest_lines = lines[0...index], lines[(index+1)..-1]
      header = header_lines.map do |line|
        line.match(/(.+):(.+)\r\n/).captures
      end.to_h
      [[:method, :url, :protocol].zip(status.split(" ")).to_h.merge!(header), rest_lines]
    end

    def handle_static_file(sock, header)
      response =
        if File.readable?(filename = "#{BASE_DIR}#{header[:url]}") && File.file?(filename)
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
      sock.write(<<~TEXT)
        #{HTTP_1_1} #{response[:status]}\r
        date: #{DateTime.now.rfc822}\r
        content-type: #{response[:content_type]}\r
        content-length: #{response[:body].bytesize+1}\r
        \r
        #{response[:body]}
      TEXT
    end

    def handle_request(sock)
      header, rest_lines = parse_header(read_content_nonblocking(sock))
      logger.info header
      raise UnsupportedProtocolError unless header[:protocol] === HTTP_1_1 || header[:method] === 'GET'
      handle_static_file(sock, header)
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
            socks.push(sock.accept)
            logger.info "#{sock} is accepted"
          else
            yield sock
            socks.delete(sock)
          end
        rescue UnsupportedProtocolError, InvalidFormatError => e
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