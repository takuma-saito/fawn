require 'logger'
require 'timeout'

module MiniWebServer
  TIMEOUT = 10
  attr_reader :workers
  def logger
    @logger ||= Logger.new(STDOUT)
  end
  class ThreadPool
    def initialize(max, min = max/2)
      @mutex = Mutex.new
      @jobs  = SizedQueue.new(max)
      @max   = max
      @spawned = 0
      @waiting = 0
      @shutdown = false
      @workers = []
      min.times { spawn_thread }
    end
    def new_worker
      proc do |id|
        Thread.current[:name] = id
        catch do |tag|
          loop do
            begin
              job = nil
              sync do
                @waiting += 1
                job = @jobs.shift
                @waiting -= 1
                throw tag unless job
              end
              Timeout.timeout(TIMEOUT) { job.(id) }
            rescue Timeout::Error => e
              logger.warn "#{e.full_message}"
              retry
            end
          end
        end
        sync { @spawned -= 1 }
        logger.info "worker #{id} is terminated"
      end
    end
    def spawn_thread
      @workers << Thread.new(@spawned += 1, &new_worker)
    end
    def sync
      @mutex.synchronize { yield }
    end
    def push(job)
      spawn_thread if (@jobs.size + @spawned) <= @max
      @jobs << job
    end
    alias :<< :push
    def shutdown
      @workers.size.times { @jobs.push(nil) }
      @workers.each(&:join)
      @jobs.close
      logger.info "stat: {job_size:%2d, waiting:%2d, workers:%2d, running:%2d}" % [
                    @jobs.size,
                    @waiting,
                    @spawned,
                    @spawned - @waiting,
                  ]
    end
  end
end

include MiniWebServer
tp = ThreadPool.new(27)

123.times do |id|
  puts "job add: #{id}"
  tp << proc do |worker_id|
    puts "start {worker_id:#{worker_id}, job_id:#{id}}"
    sleep (rand * 2.0)
    puts "finish {worker_id:#{worker_id}, job_id:#{id}}"
  end
end

tp.shutdown

