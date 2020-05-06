require_relative 'thread_pool'
require_relative 'server'

def multi_thread_run
  tp = ThreadPool.new(30)
  server = Server.new(multithread: true)
  server.run do |sock|
    tp << proc { server.handle_request(sock) }
  end
end

def single_thread_run
  server = Server.new
  server.run do |sock|
    server.handle_request(sock)
  end
end

include Fawn
single_thread_run
# multi_thread_run
