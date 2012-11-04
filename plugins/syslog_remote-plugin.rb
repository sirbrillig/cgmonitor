#!/usr/bin/ruby

# Worked up from this: http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/195565
class SyslogRemote #:nodoc:
  require 'socket'

  def initialize(syslog_server='localhost', syslog_port=514)
    @syslog_server = syslog_server
    @syslog_pri_field = 13
    @syslog_port = syslog_port
    @socket = UDPSocket.new
  end

  def send(entry, host)
    time = Time.now
    # <pri>time IP program: message
    message = "#{time.asctime} #{host} cgmonitor: #{entry}"
    @socket.send("<#{@syslog_pri_field}>#{message}", 0, @syslog_server, @syslog_port)
    message
  end
end

class SyslogRemotePlugin < CGMonitor::Plugin
  def get_node
    node = nil
    node = $1 if self.current_file.to_s =~ /\/(\we\d)\//
    node = 'unknown' if node.nil? or node.empty?
    node
  end

  def start_up
    syslog_server = ENV['SYSLOG_SERVER'] || 'localhost'
    syslog_port = ENV['SYSLOG_PORT'] || 514
    @log = SyslogRemote.new(syslog_server, syslog_port)
    info_message("Starting the SyslogRemotePlugin.  Will send logs to: #{syslog_server} on port #{syslog_port}")
  end

  def every_line(line)
    begin
      message = @log.send(line, get_node)
#       info_message(message)
    rescue Exception => e
      warning_message("Error while sending message: #{e}")
    end
  end
end
