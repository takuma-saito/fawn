require "socket"


def handle_request(sock)
  str = sock.recv(4096)
  p str.size, sock.remote_address
  sock.write(str)
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
        fail unless sock.eof?
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
