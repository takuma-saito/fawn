require 'logger'
require 'timeout'

module MiniWebServer
  TIMEOUT = 10
  def logger # TODO: ここの logger は見れるか
    @logger ||= Logger.new(STDOUT)
  end
  class ThreadPool
    def initialize(max)
      @mutex = Mutex.new
      @empty = ConditionVariable.new
      @full  = ConditionVariable.new
      @jobs  = []
      @max   = max
      @spawned = 0
      @running = 0
      @shutdown = false
    end
    def new_worker
      proc do |id|
        Thread.current[:name] = id
        loop do
          begin
            job = nil
            sync do
              @full.signal
              @empty.wait(@mutex)
              if @shutdown
                @spawned -= 1
                logger.info "#{id} is terminated"
                Thread.exit
              end
              job = @jobs.shift
              @running += 1
            end
            Timeout.timeout(TIMEOUT) { job.(id) }
            sync { @running -= 1 }
          rescue Timeout::Error => e
            logger.warn "#{e.full_message}"
            retry
          end
        end
      end
    end
    def spawned
      Thread.new(@spawned += 1, &new_worker)
    end
    def sync
      @mutex.synchronize { yield }
    end
    def push(job)
      sync do
        @full.wait(@mutex) if (@running + @jobs.size) > @max
        @jobs << job
        spawned if (@jobs.size - @running) > 0
        @empty.signal
      end
    end
    alias :<< :push
    def shutdown
      @empty.broadcast # TODO: running のプロセスの終了を待つにはどうしたらいいか
    end
  end
end

include MiniWebServer
tp = ThreadPool.new(3)

5.times do |id|
  tp << proc do |worker_id|
    puts "start {worker_id:#{worker_id}, id:#{id}}"
    sleep (rand * 2.0)
    puts "finish {worker_id:#{worker_id}, id:#{id}}"
  end
end

sleep 5.0
tp.shutdown

