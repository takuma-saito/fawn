require 'logger'
require 'timeout'

module MiniWebServer
  TIMEOUT = 10
  def logger # TODO: ここの logger は見れるか
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
      @shutdown = false
      @running  = 0
      @spawned  = 0
      @workers  = []
      min.times.map { spawn_thread }
    end
    def new_worker
      proc do |id|
        Thread.current[:name] = id
        loop do
          begin
            job = nil
            sync do
              @empty.wait(@mutex) until @jobs.size > 0
              job = @jobs.shift
              unless job
                logger.info "#{id} is terminated"
                Thread.exit
              end
              @running += 1
            end
            Timeout.timeout(TIMEOUT) { job.(id) }
            sync do
              @full.signal
              @running -= 1
            end
          rescue Timeout::Error => e
            logger.warn "#{e.full_message}"
            retry
          end
        end
      end
    end
    def spawn_thread
      @workers << Thread.new(@spawned += 1, &new_worker)
    end
    def sync
      @mutex.synchronize { yield }
    end
    def push(job)
      sync do
        @full.wait(@mutex) if @jobs.size >= @max
        @jobs << job
        spawn_thread if (@jobs.size - @running) > 0
        @empty.signal
      end
    end
    alias :<< :push
    def shutdown
      @workers.size.times { push(nil) }
      @workers.each(&:join)
    end
  end
end

include MiniWebServer
tp = ThreadPool.new(10, 1)

25.times do |id|
  puts "job add: #{id}"
  tp << proc do |worker_id|
    puts "start {worker_id:#{worker_id}, job_id:#{id}}"
    sleep (rand * 2.0)
    puts "finish {worker_id:#{worker_id}, job_id:#{id}}"
  end
end

# sleep 8.0
tp.shutdown

