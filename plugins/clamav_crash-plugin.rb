#!/usr/bin/ruby

class CGPClamAVCrash < CGMonitor::Plugin
  def start_up
    reset_count
  end

  def get_node
    node = nil
    node = $1 if self.current_file.to_s =~ /\/(\we\d)\//
    node = 'unknown' if node.nil? or node.empty?
    node
  end

  def every_line(line)
    node = get_node
    case line

    when /CGPClamAV.+Error Code=external helper timed out/
      @first_scan ||= Time.now
      if (Time.now - @first_scan) > 1.hour
        reset_count
        @first_scan = Time.now
      end

      @warning_sent[:timed_out][node] ||= false
      return if @warning_sent[:timed_out][node]

      message = "Warning: the CGPClamAV plugin on '#{node}' has apparently crashed.  I saw this: #{line}"
      warning_message(message)
      send_email(message)
      @warning_sent[:timed_out][node] = true
    end
  end

  private
  
  def reset_count
    @warning_sent = {:limit_reached => {}, :nearing_limit => {}, :timed_out => {}}
  end
end

