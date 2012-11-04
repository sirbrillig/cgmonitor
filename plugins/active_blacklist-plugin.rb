#!/usr/bin/ruby

class ActiveBlacklistPlugin < CGMonitor::Plugin
  require 'net/telnet'
  require 'socket'
  require 'resolv'

  def start_up
    @domains_seen = Hash.new
    my_options[:ehlo] ||= 'bc.edu'
    my_options[:from_address] ||= 'postmaster@bc.edu'
    my_options[:rcpt_username] ||= 'postmaster'
    my_options[:domains_to_check] ||= ['gmail.com']
    my_options[:max_time_between_outbound_mail] ||= 1.hour
    my_options[:time_between_warnings] ||= 30.minutes
    info_message("ActiveBlacklistPlugin will test SMTP sending for #{my_options[:domains_to_check].size} domains if it sees no messages sent to those hosts for #{my_options[:max_time_between_outbound_mail] / 60} minutes.")
    info_message("Domains to Check: #{my_options[:domains_to_check].join(', ')}")
    debug_message("Settings: #{my_options.inspect}")
  end

  def signal
    info_message("ActiveBlacklistPlugin will test SMTP sending for #{my_options[:domains_to_check].size} domains if it sees no messages sent to those hosts for #{my_options[:max_time_between_outbound_mail] / 60} minutes.")
    info_message("Domains to Check: #{my_options[:domains_to_check].join(', ')}")
    debug_message("Settings: #{my_options.inspect}")
  end

  def every_line(line)
    return unless line =~ /(sendmail\[\d+\]: [^:]+: to=|SMTP-\d+.+ cmd: RCPT TO:)<[^@]+@([^>]+)>/
    recipient_domain = $2
    unless my_options[:domains_to_check].include?(recipient_domain)
      debug_message("I saw a message delivered to the domain #{recipient_domain}, but that domain isn't in my list.")
      return
    end
    info_message("I saw a message delivered to the domain #{recipient_domain}; resetting timer for that domain.")
    @domains_seen[recipient_domain] = Time.now
  end

  def every_minute
    my_options[:domains_to_check].each do |domain|
      next if @domains_seen[domain] and Time.since(@domains_seen[domain]) <= my_options[:max_time_between_outbound_mail]
      info_message("Making an SMTP test for the domain #{domain}.")
      @domains_seen[domain] = Time.now
      run_test(domain)
    end
  end

  def get_response
    begin
      @srvr.waitfor(/^(\d+)\s.+?/) do |o| 
        debug_message("'#{@current_domain}' -> #{o}")
        if o =~ /^(\d{3})\s(\S+)/
          code = $1
          the_rest = $2
          if code !~ /^[23]/
            if the_rest =~ /(blacklist|blocked|blocklist)/i
              message = "I saw what might be a blocklist response from the domain #{@current_domain}: #{the_rest}"
              warning_message(message)
              send_email_buffered(message, my_options[:time_between_warnings])
            end
	    message = "SMTP test failed; '#{@current_domain}' said: #{o}"
	    message = "SMTP test failed; I said '#{@last_command}' and '#{@current_domain}' said: #{o}" if @last_command
            warning_message(message)
            send_email_buffered(message, my_options[:time_between_warnings])
            return false
          end
        end
      end
    rescue TimeoutError => e
      message = "Timed-out when waiting for a response from the domain #{@current_domain}."
      warning_message(message)
      send_email_buffered(message, my_options[:time_between_warnings])
      return false
    end
    true
  end

  def smtp_command(text)
    debug_message("'#{@current_domain}' <- #{text}")
    @last_command = text
    @srvr.puts(text)
    get_response
  end

  def smtp_connect(server)
    begin
      debug_message("Making an SMTP connection to '#{server}'.")
      @srvr = Net::Telnet::new("Host" => server, "Port" => 25, "Telnetmode" => false, "Timeout" => 60, "Prompt" => /^\d{3} /n)
    rescue TimeoutError => e
      message = "Timed-out when trying to connect to '#{server}' for the domain #{@current_domain}."
      warning_message(message)
      send_email_buffered(message, my_options[:time_between_warnings])
      return false
    end
    get_response
  end

  def get_MX_server(domain)
    mx = nil
    Resolv::DNS.open do |dns|
      mail_servers = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
      return nil unless mail_servers and not mail_servers.empty?
      highest_priority = mail_servers.first
      mail_servers.each do |server|
        highest_priority = server if server.preference < highest_priority.preference
      end
      mx = highest_priority.exchange.to_s
    end
    return mx
  end

  def run_test(domain)
    @current_domain = domain
    start_time = Time.now
    server = get_MX_server(domain)
    if server.nil? or server.empty?
      info_message("Could not find MX record for the domain #{domain}. Not sending test.")
      return false
    end
    smtp_connect(server)
    return unless smtp_command("EHLO #{my_options[:ehlo]}")
    return unless smtp_command("MAIL FROM: <#{my_options[:from_address]}>")
    return unless smtp_command("RCPT TO: <#{my_options[:rcpt_username]}@#{domain}>")
    return unless smtp_command("QUIT")
    info_message("SMTP test succeeded to '#{@current_domain}'.")
  end
end
