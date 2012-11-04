#!/usr/bin/ruby

class TestPlugin < CGMonitor::Plugin
  def start_up
    my_options[:search_phrase] ||= 'test plugin'
    info_message("Starting the TestPlugin plugin.  It will print out lines which contain the phrase '#{my_options[:search_phrase]}'.")
    @signals = 0
  end

  def every_line(line)
    return unless line =~ /#{my_options[:search_phrase]}/
    message = "this line contains the phrase '#{my_options[:search_phrase]}': #{line}" 
    info_message(message)
    send_email_buffered(message)
  end

  def signal
    message = "I got a signal!" 
    @signals += 1
    info_message(message)
    send_email(message)
  end

  def every_minute
    message = "A minute has passed and I have seen #{@signals} signals." 
    info_message(message)
    send_email_buffered(message)
    @signals = 0
  end

  def shut_down
    info_message('Stopping the TestPlugin plugin.')
  end
end
