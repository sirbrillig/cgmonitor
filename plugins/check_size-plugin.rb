#!/usr/bin/ruby -w

# $Id: check_size-plugin.rb 1125 2008-10-20 18:35:20Z swickp $

class CheckSize < CGMonitor::Plugin
  require 'pathname'

  BYTE = 1048576
  EMAIL_NOTICE = "A large queue file was detected: "

  def start_up
    my_options[:outfile] ||= "/usr/local/SystemLogs/check_queue.out"
    my_options[:queuedir] ||= "/var/CommuniGate/Queue"
    my_options[:filesize] ||= 30 # file size in megabytes
    info_message('Starting the CheckSize plugin.')
    @of = open(my_options[:outfile], "a")
  end

  def signal
    message = "CheckSize plugin received HUP.  Importing any new config file changes."
    info_message(message)
  end

  def every_second
    Pathname.glob(my_options[:queuedir]+"/*\.{msg,tmp}").each do |file|
      file.exist? ? size = file.size : next
      if size > (my_options[:filesize] * BYTE)
        logdata = "#{Time.now.to_s} #{size/BYTE}M #{file.to_s}"
        @of.puts logdata
        warning_message(EMAIL_NOTICE + logdata)
        send_email_buffered(EMAIL_NOTICE + logdata, 1.hour)
      end
    end
  end

  def shut_down
    info_message('Stopping the CheckSize plugin.')
    @of.close
  end
end
