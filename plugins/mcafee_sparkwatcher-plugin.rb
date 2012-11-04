#!/usr/bin/ruby
# Look for lines like this:
# ENQUEUERRULES rule(McAfee) conditions met

class CGPMcAfeeSparkwatcher < CGMonitor::Plugin
  def start_up
    output_file_path = '/tmp/virus_count.txt'
    @output_file = Pathname.new(output_file_path)
    @count = {}
    info_message("Will write virus count data to #{@output_file.to_s}")
  end

  def get_node
    node = nil
    node = $1 if self.current_file.to_s =~ /\/(\we\d)\//
    node = 'unknown' if node.nil? or node.empty?
    node
  end

  def every_line(line)
    if line =~ /ENQUEUERRULES rule\(McAfee\) conditions met/

      node = get_node

      @first_scan ||= Time.now
      if (Time.now - @first_scan) > 1.hour
        @count = {}
        @first_scan = Time.now
      end

      @count[node] ||= 0
      @count[node] += 1 

      if @count[node] % 4
        @output_file.open('w') do |file|
          # Tue Nov 28 09:02:08 2006
          date = Time.now.strftime('%a %b %d %T %Y')
          file.puts "#{date}"
          @count.keys.each do |n|
            file.puts "#{n}_v|#{@count[n]}"
          end
        end
      end
    end
  end
end

