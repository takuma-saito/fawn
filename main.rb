require 'logger'
require 'timeout'

module MiniWebServer
  TIMEOUT = 10
  def logger # TODO: ここの logger は見れるか
    @logger ||= Logger.new(STDOUT)
  end
  class ThreadPool
    def initialize(max, &handle_job)
      @mutex = Mutex.new
      @empty = ConditionalVariable.new
      @full  = ConditionalVariable.new
      @jobs  = []
      @max   = max
      @handle_job = handle_job
      @spawned = 0
      @running = 0
      @shutdown = false
    end
    def new_worker
      proc do |id|
        Thread.current[:name] = id
        loop do
          sync do
            @full.signal(@mutex)
            @empty.wait(@mutex)
            if @shutdown
              @spawned -= 1
              logger.info "#{id} is terminated"
              Thread.exit
            end
            job = @jobs.shift
            @running += 1
          end
          Timeout.timeout(TIMEOUT) do
            @handle_job.(job)
          end
          sync { @running -= 1 }
        rescue Timeout::Error => e
          logger.warn "#{e.full_message}"
          retry
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
        @todo << job
        spawned if (@jobs.size - @running) > 0
      end
    end
    def shutdown
      @empty.broadcast # TODO: running のプロセスの終了を待つにはどうしたらいいか
    end
  end
end
