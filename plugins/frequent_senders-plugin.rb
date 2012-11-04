#!/usr/bin/ruby

# Note that this will operate on webmail messages if run on a frontend, but will not operate on PIPE-d messages (eg: the recipients of a campusgroup).
# This is not designed to be run on a backend.
class FrequentSendersPlugin < CGMonitor::Plugin
  def start_up
    @emails_per_userid = Hash.new
    @smtp_sessions = Hash.new
    my_options[:max_emails_per_userid] ||= 120 
    my_options[:min_messages_per_userid] ||= 10
    my_options[:time_between_warnings] ||= 1.hour
    my_options[:max_time_between_messages] ||= 1.minute
    my_options[:backend_ip_addresses] ||= '192\.168\.\d\.\d+'
    info_message("Looking for userids sending at least #{my_options[:min_messages_per_userid]} emails to more than #{my_options[:max_emails_per_userid]} recipients with no two emails more than #{my_options[:max_time_between_messages] / 60} minutes apart.")
  end

  def signal
    info_message("Looking for userids sending at least #{my_options[:min_messages_per_userid]} emails to more than #{my_options[:max_emails_per_userid]} recipients with no two emails more than #{my_options[:max_time_between_messages] / 60} minutes apart.")
  end

  def user_by_message_id(message_id)
    @emails_per_userid.keys.find { |userid| @emails_per_userid[userid][:message_ids].keys.include?(message_id) }
  end

  def user_by_session_id(session_id)
    @emails_per_userid.keys.find { |userid| @emails_per_userid[userid][:smtp_id] == session_id }
  end

  def every_line(line)
    if line =~ /(SMTPI-\d+)\(\[([^\]]+)\]\) rsp: 250 .+ (will relay mail for an authenticated user|will leave the Internet|accepting mail from a client address)/

      # Count the number of recipients for an SMTP session.
      session_id = $1
      @smtp_sessions[session_id] ||= 0
      @smtp_sessions[session_id] += 1
      return

    elsif line =~ /(SMTPI-\d+)\(\[([^\]]+)\]\) (releasing stream|rsp: 250 \d+ message accepted for delivery)/

      # If the session ends, delete what we know about it.
      session_id = $1
      @smtp_sessions.delete(session_id) if @smtp_sessions[session_id]
      return

    elsif line =~ /QUEUE\(\[(\d+)\]\) header: From: (.+)/

      # If we see a From line for a message we've been counting recipients for, store it to report it later.
      message_id = $1
      from = $2
      userid = user_by_message_id(message_id)
      @emails_per_userid[userid][:from] = from if userid
      return

    elsif line =~ /QUEUE\(\[(\d+)\]\) header: Subject: (.+)/

      # If we see a subject line for a message we've been counting recipients for, store it to report it later.
      message_id = $1
      subject = $2
      userid = user_by_message_id(message_id)
      @emails_per_userid[userid][:subject] = subject if userid
      return

    elsif line =~ /QUEUE\(\[(\d+)\]\) header: Received: from \[([^\]]+)\] \(account \w+@(\w+\.)?bc\.edu\)  by \w+\.bc\.edu \(CommuniGate Pro WEBUSER/

      # If we see a subject line for a message we've been counting recipients for, store it to report it later.
      message_id = $1
      ip_address = $2
      userid = user_by_message_id(message_id)
      @emails_per_userid[userid][:last_ip] = ip_address if userid
      @emails_per_userid[userid][:webmail] = true if userid
      return

    elsif line =~ /QUEUE\(\[(\d+)\]\) header: Resent-From: <(.+?)@(\w+\.)?bc\.edu>/

      # If a message we're counting recipients for is forwarded from a BC account, don't count it.
      message_id = $1
      forwarding_userid = $2
      sender_userid = user_by_message_id(message_id)
      return unless sender_userid
      @emails_per_userid[sender_userid][:message_ids].delete(message_id)
      return

    elsif line =~ /(SMTPI-\d+)\(\[#{my_options[:backend_ip_addresses]}\]\) rsp: 250 (\w+)@.+? sender accepted/

      # If this SMTP session is coming from a backend, note the username from the MAIL FROM response (otherwise we have no way to find it).
      session_id = $1
      userid = $2
      now = Time.now
      @emails_per_userid[userid] ||= {:first_seen => now, :last_seen => now, :recipient_count => 0, :message_count => 0, :subject => nil, :message_ids => Hash.new, :smtp_id => nil, :from => nil, :last_ip => nil, :webmail => nil}
      @emails_per_userid[userid][:smtp_id] = session_id
      return
    end

    # If we see a message accepted for delivery which has recipients we've counted, then associate the session ID with the message ID and the username and the recipient count.
    if line =~ /(SMTPI-\d+)\(\[([^\]]+)\]\) \[(\d+)\] (received|received encrypted)/
      session_id = $1
      ip_address = $2
      message_id = $3
      userid = $5 if line =~ /(SMTPI-\d+)\(\[([^\]]+)\]\) \[(\d+)\] (received|received encrypted)\((\w+)@/
      userid = user_by_session_id(session_id) unless userid
      return unless @smtp_sessions[session_id] and userid

      # If it's been more than a few minutes since we last saw this userid, then start its count over.
      now = Time.now
      @emails_per_userid.delete(userid) if @emails_per_userid[userid] and (now - @emails_per_userid[userid][:last_seen]) > my_options[:max_time_between_messages]

      @emails_per_userid[userid] ||= {:first_seen => now, :last_seen => now, :recipient_count => 0, :message_count => 0, :subject => nil, :message_ids => Hash.new, :smtp_id => nil, :from => nil, :last_ip => nil, :webmail => nil}
      @emails_per_userid[userid][:message_ids][message_id] = @smtp_sessions[session_id] # Store the recipient count for that message.
      @emails_per_userid[userid][:smtp_id] = session_id
      @emails_per_userid[userid][:last_ip] = ip_address
      @smtp_sessions.delete(session_id)

      # Timestamp when this userid was last seen so we can purge it later.
      @emails_per_userid[userid][:last_seen] = now
      return
    end

    # Once the message is enqueued, we should have had time to gather all the header information, so look for frequent senders.
    return unless line =~ /QUEUE\(\[(\d+)\]\) enqueued, nTotal=/
    message_id = $1
    now = Time.now
    userid = user_by_message_id(message_id)
    return unless userid

    # Increment the number of recipients this userid has sent in the enqueued message.
    @emails_per_userid[userid][:recipient_count] += @emails_per_userid[userid][:message_ids][message_id]
    @emails_per_userid[userid][:message_count] += 1

    # If we've seen this userid send more recipients than my_options[:max_emails_per_userid], then queue a warning and start over the count for this userid.
    if (@emails_per_userid[userid][:recipient_count] > my_options[:max_emails_per_userid] and @emails_per_userid[userid][:message_count] >= my_options[:min_messages_per_userid])
      message = "The userid '#{userid}' has sent #{@emails_per_userid[userid][:message_count]} messages to a total of #{@emails_per_userid[userid][:recipient_count]} recipients since #{@emails_per_userid[userid][:first_seen].strftime('%Y-%m-%d %H:%M:%S')}. The most recent was #{(@emails_per_userid[userid][:webmail] ? 'sent from webmail ':'')}from the IP '#{@emails_per_userid[userid][:last_ip]}' with the subject '#{@emails_per_userid[userid][:subject]}' and the From address '#{@emails_per_userid[userid][:from]}'. Here's the most recent line I saw (SMTP session #{@emails_per_userid[userid][:smtp_id]}): #{line}"
      warning_message(message)
      info_message("Strange. The last message for '#{userid}' which I just reported was sent from a backend but I wasn't able to get a webmail IP address. Here's the user data: #{@emails_per_userid[userid].inspect}") if @emails_per_userid[userid][:last_ip] =~ /#{my_options[:backend_ip_addresses]}/
      send_email_buffered(message, my_options[:time_between_warnings])
      @emails_per_userid.delete(userid)
    end

    if (@emails_per_userid.size > 5000 or @smtp_sessions.size > 5000)

      # Safety valve in case we're storing too much data.
      info_message("I'm currently storing #{@emails_per_userid.size} userids and #{@smtp_sessions.size} session ids. This is a lot, so I'm resetting the count.")
      @emails_per_userid.clear
      @smtp_sessions.clear

    elsif ((@emails_per_userid.size % 100) == 0)

      # Clean out old userids every 100 userids that we store.
      @emails_per_userid.each_key do |userid|
        @emails_per_userid.delete(userid) if ((now - @emails_per_userid[userid][:last_seen]) > my_options[:max_time_between_messages])
      end
    end
  end
end
