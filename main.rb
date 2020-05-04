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
      @empty = ConditionVariable.new
      @full  = ConditionVariable.new
      @jobs  = []
      @max   = max
      @min   = min
      @spawned = 0
      @waiting = 0
      @shutdown = false
      @workers = []
      @min.times do
        sync { spawn_thread }
      end
    end
    def new_worker(initial_job)
      proc do |id|
        Thread.current[:name] = id
        catch do |tag|
          job = initial_job
          loop do
            begin
              sync do
                @full.signal
                @waiting += 1
                throw tag if @shutdown
                @empty.wait(@mutex) while @jobs.empty?
                throw tag if @shutdown
                job = @jobs.shift || fail
                @waiting -= 1
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
    def spawn_thread(initial_job = nil)
      @workers << Thread.new(@spawned += 1, &new_worker(initial_job))
    end
    def sync
      @mutex.synchronize { yield }
    end
    def push(job)
      return if @shutdown 
      sync do
        is_full = (@spawned - @waiting + @jobs.size) > @max
        @full.wait(@mutex) if is_full
        @jobs << job
        (@jobs.size - 1 - @waiting) > 0 && !is_full ?
          spawn_thread(@jobs.shift) : @empty.signal
      end
    end
    alias :<< :push
    def shutdown
      sync do
        @shutdown = true
        @empty.broadcast
        @full.broadcast
        logger.info "stat: {job_size:%2d, waiting:%2d, workers:%2d, running:%2d}" % [
                      @jobs.size,
                      @waiting,
                      @spawned,
                      @spawned - @waiting,
                    ]
      end
    end
  end
end

include MiniWebServer
tp = ThreadPool.new(37)

123.times do |id|
  puts "job add: #{id}"
  tp << proc do |worker_id|
    puts "start {worker_id:#{worker_id}, job_id:#{id}}"
    sleep (rand * 2.0)
    puts "finish {worker_id:#{worker_id}, job_id:#{id}}"
  end
end

tp.shutdown
tp.workers.each(&:join)

