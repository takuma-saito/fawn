require_relative 'thread_pool'
require_relative 'server'

include Fawn

Server.run do |sock|
  handle_request(sock)
end

