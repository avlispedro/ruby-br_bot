module Irc

  require 'socket'
  require 'thread'

  # wrapped TCPSocket for communication with the server.
  # emulates a subset of TCPSocket functionality
  class IrcSocket
    # total number of lines sent to the irc server
    attr_reader :lines_sent
    
    # total number of lines received from the irc server
    attr_reader :lines_received
    
    # delay between lines sent
    attr_reader :sendq_delay
    
    # max lines to burst
    attr_reader :sendq_burst
    
    # server:: server to connect to
    # port::   IRCd port
    # host::   optional local host to bind to (ruby 1.7+ required)
    # create a new IrcSocket
    def initialize(server, port, host, sendq_delay=2, sendq_burst=4)
      @server = server.dup
      @port = port.to_i
      @host = host
      @lines_sent = 0
      @lines_received = 0
      if sendq_delay
        @sendq_delay = sendq_delay.to_f
      else
        @sendq_delay = 2
      end
      @last_send = Time.new - @sendq_delay
      @burst = 0
      if sendq_burst
        @sendq_burst = sendq_burst.to_i
      else
        @sendq_burst = 4
      end
    end
    
    # open a TCP connection to the server
    def connect
      if(@host)
        begin
          @sock=TCPSocket.new(@server, @port, @host)
        rescue ArgumentError => e
          $stderr.puts "Your version of ruby does not support binding to a "
          $stderr.puts "specific local address, please upgrade if you wish "
          $stderr.puts "to use HOST = foo"
          $stderr.puts "(this option has been disabled in order to continue)"
          @sock=TCPSocket.new(@server, @port)
        end
      else
        @sock=TCPSocket.new(@server, @port)
      end 
      @qthread = false
      @qmutex = Mutex.new
      @sendq = Array.new
      if (@sendq_delay > 0)
        @qthread = Thread.new { spooler }
      end
    end

    def sendq_delay=(newfreq)
      debug "changing sendq frequency to #{newfreq}"
      @qmutex.synchronize do
        @sendq_delay = newfreq
        if newfreq == 0 && @qthread
          clearq
          Thread.kill(@qthread)
          @qthread = false
        elsif(newfreq != 0 && !@qthread)
          @qthread = Thread.new { spooler }
        end
      end
    end

    def sendq_burst=(newburst)
      @qmutex.synchronize do
        @sendq_burst = newburst
      end
    end

    # used to send lines to the remote IRCd
    # message: IRC message to send
    def puts(message)
      @qmutex.synchronize do
        # debug "In puts - got mutex"
        puts_critical(message)
      end
    end

    # get the next line from the server (blocks)
    def gets
      reply = @sock.gets
      @lines_received += 1
      if(reply)
        reply.strip!
      end
      debug "RECV: #{reply.inspect}"
      reply
    end

    def queue(msg)
      if @sendq_delay > 0
        @qmutex.synchronize do
          # debug "QUEUEING: #{msg}"
          @sendq.push msg
        end
      else
        # just send it if queueing is disabled
        self.puts(msg)
      end
    end

    def spooler
      while true
        spool
        sleep 0.2
      end
    end

    # pop a message off the queue, send it
    def spool
      unless @sendq.empty?
        now = Time.new
        if (now >= (@last_send + @sendq_delay))
          # reset burst counter after @sendq_delay has passed
          @burst = 0
          debug "in spool, resetting @burst"
        elsif (@burst >= @sendq_burst)
          # nope. can't send anything
          return
        end
        @qmutex.synchronize do
          debug "(can send #{@sendq_burst - @burst} lines, there are #{@sendq.length} to send)"
          (@sendq_burst - @burst).times do
            break if @sendq.empty?
            puts_critical(@sendq.shift)
          end
        end
      end
    end

    def clearq
      unless @sendq.empty?
        @qmutex.synchronize do
          @sendq.clear
        end
      end
    end

    # flush the TCPSocket
    def flush
      @sock.flush
    end

    # Wraps Kernel.select on the socket
    def select(timeout)
      Kernel.select([@sock], nil, nil, timeout)
    end

    # shutdown the connection to the server
    def shutdown(how=2)
      @sock.shutdown(how)
    end

    private
    
    # same as puts, but expects to be called with a mutex held on @qmutex
    def puts_critical(message)
      # debug "in puts_critical"
      debug "SEND: #{message.inspect}"
      @sock.send(message + "\n",0)
      @last_send = Time.new
      @lines_sent += 1
      @burst += 1
    end

  end

end