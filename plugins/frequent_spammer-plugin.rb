#!/usr/bin/ruby

class FrequentSpammerPlugin < CGMonitor::Plugin
  def start_up
    @emails_per_address = Hash.new
    @current_offenders = Array.new
    @unclaimed_recipients = Hash.new
    mark_time(:last_cleaned)
    my_options[:min_messages_per_address] ||= 3
    my_options[:max_recipients_per_address] ||= 10
    my_options[:time_between_warnings] ||= 20.minutes
    my_options[:max_time_between_messages] ||= 30.minutes
    my_options[:clean_addresses_every] ||= 10.minutes
    my_options[:write_status_to_file] ||= "/usr/local/hobbit/client/tmp/frequent_spammers"
    my_options[:safelist_addresses] ||= Array.new
    show_config
    self.ensure_emails_are_sent = true
  end

  def show_config
    info_message("Looking for addresses sending at least #{my_options[:min_messages_per_address]} spam messages outbound to more than #{my_options[:max_recipients_per_address]} recipients with no two emails more than #{my_options[:max_time_between_messages] / 60} minutes apart.")
    info_message("I will write any such addresses to '#{my_options[:write_status_to_file]}'")
    info_message("I will ignore the following safelisted addresses: #{my_options[:safelist_addresses].join(', ')}")
    info_message("I will clean out old addresses every #{my_options[:clean_addresses_every] / 60} minutes.")
  end

  def signal
    show_config
  end

  def write_status
    info_message("Writing status file to '#{my_options[:write_status_to_file]}' including #{@current_offenders.size} offenders.")
    file = Pathname.new(my_options[:write_status_to_file])
    begin
      file.open('w') { |out| out.puts @current_offenders }
    rescue Exception => e
      info_message("Error while writing status file '#{my_options[:write_status_to_file]}': "+e)
    end
  end

  def clean_old_addrs
    mark_time(:last_cleaned)
    @emails_per_address.each_key do |address|
      if ((Time.now - @emails_per_address[address][:last_seen]) > my_options[:max_time_between_messages])
        @emails_per_address.delete(address)
        @current_offenders.delete(address)
        write_status
      end
    end
  end

  def check_for_offenders(address)
    return false unless @emails_per_address[address]
    if (@emails_per_address[address][:messages].size >= my_options[:min_messages_per_address] and @emails_per_address[address][:recipients] > my_options[:max_recipients_per_address])

      message = "The sender '#{address}' has sent #{@emails_per_address[address][:messages].size} spam messages to #{@emails_per_address[address][:recipients]} recipients recently. The most recent had the Subject '#{@emails_per_address[address][:subject]}'. Here's the most recent line I saw: #{@emails_per_address[address][:messages].last}"

      warning_message(message)
      send_email_buffered(message, my_options[:time_between_warnings])
      @current_offenders << address unless @current_offenders.include?(address)
      write_status

      # Reset the number of messages and recipients for this sender.
      @emails_per_address[address][:messages].clear
      @emails_per_address[address][:recipients] = 0
      @emails_per_address[address][:mids].clear
      return true
    end
    false
  end

  def every_minute
    clean_old_addrs if time_since_mark(:last_cleaned) >= my_options[:clean_addresses_every]
  end

  def every_line(line)

    if line =~ /(\S+): Milter add: header: X-Proofpoint-Spam-Details:/
      mid = $1

      if line =~ /Milter add: header: X-Proofpoint-Spam-Details: rule=quarantine_spam_outbound_passthrough policy=quarantine .+? passthough_outbound_spam \(from: ([^,]+), subject: ([^\)]+)\)/
        address = $1
        subject = $2
        if my_options[:safelist_addresses].include?(address)
          @emails_per_address.delete(address) 
          @current_offenders.delete(address)
          @unclaimed_recipients.delete(mid)
          return
        end
        now = Time.now
        message = "I noticed that the sender '#{address}' has sent a message marked as spam by Proofpoint. Here's the most recent line I saw: #{line}"
        info_message(message)
        @emails_per_address[address] ||= {:last_seen => now, :messages => Array.new, :recipients => 0, :mids => Array.new, :subject => subject}
        if ((now - @emails_per_address[address][:last_seen]) > my_options[:max_time_between_messages])
          @emails_per_address.delete(address) 
          @current_offenders.delete(address)
          write_status
        end
        @emails_per_address[address] ||= {:last_seen => now, :messages => Array.new, :recipients => 0, :mids => Array.new, :subject => subject}
        @emails_per_address[address][:messages] << line
        @emails_per_address[address][:mids] << mid
        @emails_per_address[address][:last_seen] = now
        @emails_per_address[address][:subject] = subject

        if @unclaimed_recipients[mid]
          @emails_per_address[address][:recipients] += @unclaimed_recipients[mid]
        else
          @emails_per_address[address][:recipients] += 1
        end
        check_for_offenders(address)
      end

      # Are there cases where X-Proofpoint-Spam-Details would not be added and
      # an mid might stay around forever? Probably. Hence the safety valve.
      @unclaimed_recipients.delete(mid)

    elsif line =~ /(\S+): from=<([^>]+@(\w*mail\.)?bc\.edu)>, size=\d+, class=\d+, nrcpts=(\d+),/
      mid = $1
      sender = $2
      rcpts = $4

      # This should never happen more than once per message, right?
      @unclaimed_recipients[mid] = rcpts.to_i
    end

    # Safety valve in case we're storing too much data.
    if (@unclaimed_recipients.size > 5000)
      info_message("I'm currently storing #{@unclaimed_recipients.size} message IDs. This is a lot, so I'm resetting the count.")
      @unclaimed_recipients.clear
    end
    if (@emails_per_address.size > 5000)
      info_message("I'm currently storing #{@emails_per_address.size} email addresses. This is a lot, so I'm resetting the count.")
      @emails_per_address.clear
      @current_offenders.clear
      write_status
    end
  end
end
