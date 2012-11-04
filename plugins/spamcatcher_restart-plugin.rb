#!/usr/bin/ruby
# Look for lines like this:
# EXTFILTER(SpamCatcher) inp(23): * Restarting the engine

class CGPSpamCatcherRestart < CGMonitor::Plugin
  def every_line(line)
    return unless line =~ /EXTFILTER\(SpamCatcher\) inp\(23\): \* Restarting the engine/

    message = "I've just noticed that the CGPSpamCatcher plugin has restarted."
    info_message(message)
    send_email(message)
  end
end

