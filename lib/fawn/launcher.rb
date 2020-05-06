require_relative 'thread_pool'
require_relative 'server'

module Fawn
  module Launcher
    module SingleThread
      def run; single_thread_run; end
    end
    module MultiThread
      def run; multi_thread_run; end
    end
    include SingleThread
    module_function :run
    
    def multi_thread_run
      tp = ThreadPool.new(10)
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
  end
end
