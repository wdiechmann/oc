require "socket"
require "timeout"
module EpMonitor
  class Server
    def initialize(agent,port:)
      @agent = agent
      @server = TCPServer.new("127.0.0.1",port)
    end
    def port = @server.addr[1]
    def run
      @thread = Thread.new do
        loop do
          socket = @server.accept
          begin
            Timeout.timeout(1) do
              request = socket.gets(1024).to_s
              path = request.split(" ")[1]
              statistics = if path == "/health/live"
                {}
              else
                begin
                  @agent.statistics
                rescue StandardError
                  {ready: false,queue: {pending: 0,quarantined: 0},status: "unavailable"}
                end
              end
              status,body,type = case path
              when "/health/live" then [200,JSON.generate(alive: true),"application/json"]
              when "/health/ready" then [statistics[:ready] ? 200 : 503,JSON.generate(ready: statistics[:ready]),"application/json"]
              when "/status" then [200,JSON.generate(statistics),"application/json"]
              when "/metrics" then [200,"monitor_queue_pending #{statistics[:queue][:pending]}\nmonitor_queue_quarantined #{statistics[:queue][:quarantined]}\nmonitor_ready #{statistics[:ready] ? 1 : 0}\n","text/plain"]
              else [404,"{}","application/json"]
              end
              status = 405 unless request.start_with?("GET ")
              socket.write("HTTP/1.1 #{status} Result\r\nContent-Type: #{type}\r\nCache-Control: no-store\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
            end
          rescue IOError,Timeout::Error,Errno::EPIPE
            nil
          ensure socket.close end
        end
      rescue IOError,Errno::EBADF
        nil
      end
    end
    def stop
      @server.close
      @thread&.join(2)
    end
  end
end
