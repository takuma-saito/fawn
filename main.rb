require 'logger'
require 'timeout'

module Fawn
  TIMEOUT = 10
  attr_reader :workers
  def logger
    @logger ||= Logger.new(STDOUT)
  end
  class ThreadPool
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
            Timeout.timeout(TIMEOUT) { job.(id) }
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

include MiniWebServer
tp = ThreadPool.new(4)

15.times do |id|
  puts "job add: #{id}"
  tp << proc do |worker_id|
    puts "start {worker_id:#{worker_id}, job_id:#{id}}"
    sleep (rand * 2.0)
    puts "finish {worker_id:#{worker_id}, job_id:#{id}}"
  end
end

tp.shutdown

