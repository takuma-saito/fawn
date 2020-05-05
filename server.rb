require "socket"

CHUNK_SIZE = 512
CRLF = "\r\n"

def read_header(sock)
  String.new.then do |str|
    loop do
      str << (t = sock.recv(CHUNK_SIZE))
      break str if t.size < CHUNK_SIZE
    end
  end
end

def parse_header(str)
  lines = str.lines
  version = lines.shift
  index = lines.find_index {|line| line === CRLF }
  fail if index.nil?
  header_lines, rest_lines = lines[0...index], lines[(index+1)..-1]
  header = header_lines.map do |line|
    line.match(/(.+):(.+)\r\n/).captures
  end.to_h
  [[:method, :url, :protocol].zip(version.split(" ")).to_h.merge!(header), rest_lines]
end

def handle_request(sock)
  header, rest_lines = parse_header(read_header(sock)).tap {|header, _| p header }
  sock.write(header.inspect)
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
        puts "#{sock} is accepted"
      else
        handle_request(sock)
        sock.close
        socks.delete(sock)
        puts "#{sock} is gone"
      end
    rescue Errno::ECONNRESET => e
      warn "#{e.full_message}"
      break
    end
  end
end

run
