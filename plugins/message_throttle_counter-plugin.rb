#!/usr/bin/ruby

class MessageThrottleCounterPlugin < CGMonitor::Plugin
  def start_up
    @emails_per_userid = Hash.new
    my_options[:max_emails_per_userid] ||= 200
    my_options[:time_between_warnings] ||= 24.hours
    my_options[:max_time_to_notice_messages] ||= 30.minutes
    my_options[:backend_ip_addresses] ||= '192\.168\.\d\.\d+'
    info_message("Looking for userids sending more than #{my_options[:max_emails_per_userid]} emails within #{my_options[:max_time_to_notice_messages] / 60} minutes.")
  end

  def user_by_session_id(session_id)
    @emails_per_userid.keys.find { |userid| @emails_per_userid[userid][:smtp_id] == session_id }
  end

  def every_line(line)
    if line =~ /(SMTPI-\d+)\(\[#{my_options[:backend_ip_addresses]}\]\) rsp: 250 (\w+)@.+? sender accepted/

      # If this SMTP session is coming from a backend, note the username from the MAIL FROM response (otherwise we have no way to find it).
      session_id = $1
      userid = $2
      now = Time.now
      @emails_per_userid[userid] ||= {:first_seen => now, :last_seen => now, :recipient_count => 0, :message_count => 0, :subject => nil, :message_id => nil, :smtp_id => nil}
      @emails_per_userid[userid][:smtp_id] = session_id
      return
    end

    # Count a message when we see one accepted.
    return unless line =~ /(SMTPI-\d+)\(\[([^\]]+)\]\) \[(\d+)\] (received|received encrypted)/
    session_id = $1
    ip_address = $2
    message_id = $3
    userid = $5 if line =~ /(SMTPI-\d+)\(\[([^\]]+)\]\) \[(\d+)\] (received|received encrypted)\((\w+)@/
    userid = user_by_session_id(session_id) unless userid
    return unless userid

    # Timestamp when this userid if we've never seen it before was last seen so we can purge it later.
    now = Time.now
    @emails_per_userid[userid] ||= {:first_seen => now, :last_seen => now, :recipient_count => 0, :message_count => 0, :subject => nil, :message_id => nil, :smtp_id => nil}
    @emails_per_userid[userid][:message_id] = message_id

    time_since_first = (now - @emails_per_userid[userid][:first_seen])
    # If it's been more than my_options[:max_time_to_notice_messages] since we first saw a message from this userid, then start its count over.
    if time_since_first > my_options[:max_time_to_notice_messages]
      @emails_per_userid.delete(userid)
    else

      # Increment the number of messages this userid has sent.
      @emails_per_userid[userid][:message_count] += 1

      # If we've seen this userid send more recipients than my_options[:max_emails_per_userid], then queue a warning and start over the count for this userid.
      if (@emails_per_userid[userid][:message_count] > my_options[:max_emails_per_userid])
        message = "The userid '#{userid}' has sent a lot of messages (#{@emails_per_userid[userid][:message_count]}) in the last #{(time_since_first / 60).to_i} minutes. Here's the most recent line: #{line}"
        warning_message(message)
        send_email_buffered(message, my_options[:time_between_warnings])
        @emails_per_userid.delete(userid)
      end
    end

    if (@emails_per_userid.size > 5000)

      # Safety valve in case we're storing too much data.
      info_message("I'm currently storing #{@emails_per_userid.size} userids. This is a lot, so I'm resetting the count.")
      @emails_per_userid.clear

    elsif ((@emails_per_userid.size % 100) == 0)

      # Clean out old userids every 100 userids that we store.
      @emails_per_userid.keys.each { |userid| @emails_per_userid.delete(userid) if (now - @emails_per_userid[userid][:first_seen]) > my_options[:max_time_to_notice_messages] }
    end
  end
end
