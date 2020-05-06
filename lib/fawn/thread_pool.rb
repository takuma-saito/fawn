require 'timeout'
require_relative 'logger'

module Fawn
  TIMEOUT = 10
  attr_reader :workers
  class ThreadPool
    include Fawn::Logger
    def initialize(thread_nums)
      @mutex = Mutex.new
      @jobs  = SizedQueue.new(thread_nums)
      @thread_nums = thread_nums
      @shutdown = false
      @workers = thread_nums.times.map {|id| spawn_thread(id) }
    end
    def new_worker
      proc do |id|
        Thread.current[:name] = id
        loop do
          begin
            job = @jobs.shift
            break unless job
            Timeout.timeout(TIMEOUT) do
              logger.info "worker #{id} is processing"
              job.(id)
              logger.info "worker #{id} finish processing"
            end
          rescue Timeout::Error => e
            logger.warn "#{e.full_message}"
            retry
          end
        end
        logger.info "worker #{id} is terminated"
      end
    end
    def spawn_thread(id)
      Thread.new(id, &new_worker)
    end
    def push(job)
      @jobs << job
    end
    alias :<< :push
    def shutdown
      @workers.size.times { @jobs.push(nil) }
      @workers.each(&:join)
      @jobs.close
    end
  end
end