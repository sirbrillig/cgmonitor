#!/usr/bin/ruby

class SpoofedFromAddressPlugin < CGMonitor::Plugin
  def start_up
    @smtp_sessions = Hash.new
    my_options[:max_number_of_smtp_sessions] ||= 500
    info_message("I will look for messages from non-BC hosts that list @bc.edu addresses as their sender.")
  end

  def every_line(line)
    @smtp_sessions.clear if @smtp_sessions.size > my_options[:max_number_of_smtp_sessions]

    if line =~ /\]: ([^:]+): from=<([^>]+)>, .+, relay=(\S+)/
      # Example: sendmail[24265]: n09G18sG024265: from=<ESC1102401528476_1101535296815_9204@in.constantcontact.com>, size=18306, class=0, nrcpts=1, msgid=<1102401528476.1101535296815.9204.1.15105546@scheduler>, proto=ESMTP, daemon=MTA, relay=ccm23.constantcontact.com [208.75.123.131]
      smtp_id = $1
      sender_address = $2
      relay_server = $3
      return if relay_server =~ /\.bc\.edu$/i
      return if relay_server =~ /localhost\.localdomain$/i
      return unless sender_address =~ /@bc\.edu$/i
      @smtp_sessions[smtp_id] = { :sender_address => sender_address, :relay_server => relay_server }
      
    elsif line =~  /\]: ([^:]+): to=<([^>]+)>, .+, stat=discarded/
      # Example: Jan  9 14:18:16 superbia sendmail[13872]: n09JIB9i013872: to=<kew@bc.edu>, delay=00:00:02, pri=31802, stat=discarded
      smtp_id = $1
      return unless @smtp_sessions[smtp_id]
      @smtp_sessions.delete(smtp_id)

    elsif line =~  /\]: ([^:]+): to=<([^>]+)>, .+, relay=(\S+)/
      # Example: Jan  9 14:42:56 superbia sendmail[3477]: n09JgthK003475: to=<joanne.larosee@bc.edu>, delay=00:00:00, xdelay=00:00:00, mailer=esmtp, pri=124848, relay=[192.168.1.15] [192.168.1.15], dsn=2.0.0, stat=Sent (266668137 message accepted for 
      smtp_id = $1
      relay_server = $3
      return unless relay_server =~ /192\.168\./
      return unless @smtp_sessions[smtp_id]
      session = @smtp_sessions[smtp_id]
      message = "I saw a message from '#{session[:sender_address]}' relayed through '#{session[:relay_server]}'."
      warning_message(message)
    end
  end
end
