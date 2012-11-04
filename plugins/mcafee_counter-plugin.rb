#!/usr/bin/ruby

class CGPMcAfeeCounter < CGMonitor::Plugin
  def start_up
    reset_count
    @warning_count = 9900
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

    when /McAfee.+REJECTED License limit reached/
      @first_scan ||= Time.now
      if (Time.now - @first_scan) > 1.hour
        reset_count
        @first_scan = Time.now
      end

      @warning_sent[:limit_reached][node] ||= false
      return if @warning_sent[:limit_reached][node]

      message = "Warning: the CGPMcAfee plugin on '#{node}' has apparently reached its license limit.  I saw this: #{line}"
      warning_message(message)
      send_email(message)
      @warning_sent[:limit_reached][node] = true

    when /ENQUEUERRULES rule\(McAfee\) conditions met/
      @first_scan ||= Time.now
      if (Time.now - @first_scan) > 1.hour
        reset_count
        @first_scan = Time.now
      end

      @count[node] ||= 0
      @warning_sent[:nearing_limit][node] ||= false
      return if @warning_sent[:nearing_limit][node]
      @count[node] += 1 

      if @count[node] >= @warning_count
        message = "I've just noticed that the CGPMcAfee plugin on #{node} has scanned #{@warning_count} messages this hour.  It may be nearing its limit."
        warning_message(message)
        send_email(message)
        @warning_sent[:nearing_limit][node] = true
      end
    end
  end

  private
  
  def reset_count
    @count = {}
    @warning_sent = {:limit_reached => {}, :nearing_limit => {}}
  end
end
