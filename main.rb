require 'logger'
require 'timeout'

module MiniWebServer
  TIMEOUT = 10
  attr_reader :workers
  def logger # TODO: ここの logger は見れるか
    @logger ||= Logger.new(STDOUT)
  end
  class ThreadPool
    def initialize(max, min = max)
      @mutex = Mutex.new
      @empty = ConditionVariable.new
      @full  = ConditionVariable.new
      @jobs  = []
      @max   = max
      @min   = min
      @spawned = 0
      @running = 0
      @shutdown = false
      @workers = []
      @min.times do
        sync { spawn_thread }
      end
    end
    def new_worker
      proc do |id|
        Thread.current[:name] = id
        catch do |tag|
          loop do
            begin
              job = nil
              sync do
                while @jobs.empty?
                  @empty.wait(@mutex) if @jobs.size == 0
                  throw tag if @shutdown
                end
                job = @jobs.shift || fail
                @running += 1
              end
              Timeout.timeout(TIMEOUT) { job.(id) }
              sync do
                throw tag if @shutdown
                @running -= 1
                @full.signal
              end
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
      sync do
        @full.wait(@mutex) if (@running + @jobs.size) > @max
        @jobs << job
        @empty.signal
      end
    end
    alias :<< :push
    def shutdown
      sync do
        @shutdown = true
        @empty.broadcast
        @full.broadcast
        logger.info "stat: {job_size:%2d, running:%2d, workers:%2d}" % [
                      @jobs.size,
                      @running,
                      @workers.size
                    ]
      end
    end
  end
end

include MiniWebServer
tp = ThreadPool.new(12)

35.times do |id|
  puts "job add: #{id}"
  tp << proc do |worker_id|
    puts "start {worker_id:#{worker_id}, job_id:#{id}}"
    sleep (rand * 2.0)
    puts "finish {worker_id:#{worker_id}, job_id:#{id}}"
  end
end

tp.shutdown
tp.workers.each(&:join)

