#!/usr/bin/ruby

class AtMailPlugin < CGMonitor::Plugin
  def start_up
    info_message('Starting the AtMail plugin to report IP addresses which still use the @mail.bc.edu format.')
    @ip_expression_to_consider = /^136\.167\./
    @ip_expression_to_ignore = /^136\.167\.2\.(42|43|55|48|49|50|254)$/
    ensure_emails_are_sent = true
  end

  def every_line(line)
    return unless line =~ /header: Received: from .+?\[([^\]]+)\].+?by (acedia|ira|invida|superbia|fe\d).+?for .+?(\w+\@mail\.bc\.edu)/i
    ip = $1
    address = $3
    return unless ip =~ @ip_expression_to_consider
    return if ip =~ @ip_expression_to_ignore
    message = "I just saw the IP address '#{ip}' send a message to '#{address}' using the incorrect @mail.bc.edu format: #{line}"
    warning_message(message)
    #send_email_buffered(message, 24.hours)
  end
end
