#!/usr/bin/ruby

class EmailStats < CGMonitor::Plugin
  require 'yaml'
  require 'fileutils'
  require 'time'

  def current_month
    Time.now.strftime('%Y-%m')
  end

  def current_day
    Time.now.strftime('%Y-%m-%d')
  end

  # Store data in a hash keyed by day for the entire month.
  def reset_data
    @data ||= {}
    @data[current_day] = { 
      :missed_times => [],
      :inbound_smtp_attempt => 0,
      :inbound_smtp => 0,
      :inbound_enqueued_messages => 0,
      :inbound_enqueued_recipients => 0,
      :inbound_enqueued_for_bc => 0,
      :inbound_enqueued_for_relay => 0,
      :forwarded => 0,
      :inbound_delivered => 0,
      :outbound_relayed_messages => 0,
      :hotmail_rejection => 0,
      :hotmail_accepted => 0,
      :hotmail_total => 0,
      :spam_messages => 0,
      :probably_spam_messages => 0,
      :messages_spamcatcher_scored => 0,
      :messages_rejected => 0,
      :messages_rejected_spamhaus => 0,
      :messages_rejected_bad_address => 0,
      :messages_rejected_banned_text => 0,
      :messages_rejected_no_address => 0,
      :messages_rejected_quota_full => 0,
      :greylisted => 0,
      :report_message_generated => 0,
      :mail_delayed_warning => 0,
      :corrected_mailbox => 0,
    }
    # Add a timestamp when writing and add note if we've missed any time.
    @data[:last_written] = Time.now
    info_message("Data reset for #{current_day.inspect}.")
  end

  # Purge the @data hash of data older than 2 months + the "recent" time period.
  def clean_old_data
    oldest_day = Time.now - (2.months + @days_of_data_to_keep.days)
    new_data = Hash.new
    @data.each_pair do |k,v|
      if k == :last_written
        new_data[k] = v
      elsif Time.parse(k) >= oldest_day
        new_data[k] = v
      end
    end
    @data = new_data
  end

  def data_file(month=current_month)
    @data_file_path+"#{month}.dat"
  end

  def recent_file
    @data_file_path+"recent.yaml"
  end

  # Dump the data into a YAML-encoded file for the month.
  def write_data(month=current_month)

    @data[:last_written] = Time.now

    # Write data for the current month to the monthly file.
    # Write to temp file first, then move it to the real file and delete the
    # temp.
    file = data_file(month)
    temp_file = Pathname.new(file.to_s+'.tmp')
    monthly_data = Hash.new
    @data.each_pair do |k,v|
      if k == :last_written
        monthly_data[k] = v
      elsif Time.parse(k).strftime('%Y-%m') == month
        monthly_data[k] = v
      end
    end
    temp_file.open('w') { |f| YAML::dump(monthly_data, f) }
    FileUtils.copy(temp_file, file)
    info_message("Wrote monthly email stats to file #{file.to_s}")
#     temp_file.unlink

    # Also write to the 'recent' file, but only the last @days_of_data_to_keep days.
    file = recent_file()
    temp_file = Pathname.new(file.to_s+'.tmp')
    oldest_day = Time.now - @days_of_data_to_keep.days
    recent_data = Hash.new
    @data.each_pair do |k, v|
      if k == :last_written
        recent_data[k] = v
      elsif Time.parse(k) >= oldest_day
        recent_data[k] = v
      end
    end
    temp_file.open('w') { |f| YAML::dump(recent_data, f) }
    FileUtils.copy(temp_file, file)
    info_message("Wrote recent email stats to file #{file.to_s}")
#     temp_file.unlink
  end

  # If a data file exists for the current month, read it and import the YAML
  # data.
  def read_data
    if data_file.exist?
      data_file.open('r') { |f| @data.merge!(YAML::load(f)) }
      info_message("Read email stats from file #{data_file.to_s}")

      # Note times during which data was not being read.
      if @data[:last_written]
        seconds_since_write = (Time.now - @data[:last_written])
        if seconds_since_write > (60*60*24)
          value = (seconds_since_write/60/60/24).round
          name = 'day'
        elsif seconds_since_write > (60*60)
          value = (seconds_since_write/60/60).round
          name = 'hour'
        elsif seconds_since_write > (60)
          value = (seconds_since_write/60).round
          name = 'minute'
        else
          value = seconds_since_write.round
          name = 'second'
        end
        time_difference = "#{value} #{name}#{(value == 1 ? '':'s')}"
        info_message("Prior to this read, the last write to the file was: #{@data[:last_written].to_s} (#{time_difference} ago)")
        if @data[current_day]
          @data[current_day][:missed_times] ||= []
          @data[current_day][:missed_times] << "#{@data[:last_written].to_s} - #{Time.now.to_s}"
        end
      end
    end
    if recent_file.exist?
      recent_file.open('r') { |f| @data.merge!(YAML::load(f)) }
      info_message("Read recent email stats from file #{recent_file.to_s}")
    end
  end

  def start_up
    @data_file_path = Pathname.new('/var/log/email_stats')
    @stop = false
    @days_of_data_to_keep = (3 * 31)

    reset_data
    read_data

    info_message("The EmailStats plugin will write its output in #{@data_file_path}")

    if not @data_file_path.exist?
      @data_file_path.mkpath()
    end

    if not @data_file_path.exist?
      warning_message("The data directory #{@data_file_path} could not be created.")
      @stop = true
    end

    if not @data_file_path.directory?
      warning_message("The data directory #{@data_file_path} exists but is not a directory.")
      @stop = true
    end

    if not @data_file_path.writable?
      warning_message("The data directory #{@data_file_path} exists but is not writable.")
      @stop = true
    end
  end

  def every_line(line)
    return if @stop

    # When we finish a day, write the data out, and set up the new blank data
    # for today.
    @today ||= current_day
    @this_month ||= current_month
    if current_day != @today
      info_message("It appears to be a new day (#{current_day.inspect} != #{@today.inspect}).  Saving data and resetting for today.")
      if current_month != @this_month
        info_message("It appears to be a new month (#{current_month.inspect} != #{@this_month.inspect}).  Resetting monthly data.")
        write_data(@this_month)
        clean_old_data
      else
        write_data
      end
      reset_data
      @today = current_day
      @this_month = current_month
    end

    unless @data[@today].kind_of? Hash
      warning_message("The data hash for today (#{@today.inspect}) is not a hash for some reason. This should not happen. The data for today is instead: #{@data[@today].inspect}")
      return
    end

    case line

    # Seeing the following means that we've received a new inbound SMTP
    # attempted connection.
    when /SMTPI-.+ got connection on/
      add_one(:inbound_smtp_attempt)

    # Seeing the following means that we're starting a new inbound SMTP
    # session.
    when /SMTPI-.+ rsp: 220 fe1.bc.edu ESMTP CommuniGate Pro/
      add_one(:inbound_smtp)

    # This means a single inbound message (with any number of recipients) is
    # being accepted for an attempt to be delivered.
    when /SMTPI-.+ rsp: 250 \d+ message accepted for delivery/
      add_one(:inbound_enqueued_messages)

    # This means a copy of a single inbound message (for one recipient) is
    # being accepted for an attempt to be delivered.
    when /SMTPI-.+ rsp: 250 (.+) (will leave the Internet|will relay mail for an authenticated user)/
      add_one(:inbound_enqueued_recipients)
      if $1 =~ /@(mail\.)?bc\.edu/i
        add_one(:inbound_enqueued_for_bc)
      else
        add_one(:inbound_enqueued_for_relay)
      end

    # This means that a user is attempting to forward a copy of a message to
    # another address with a rule (does not include those who forward by
    # mailroutingaddress such as alumni, applicants, and forwarding
    # mailgroups).
    when /LOCALRULES\(.+ rule '#Redirect'\(Mirror\) ->/
      add_one(:forwarded)

    # This means that a copy of a message has been successfully delivered to a
    # mailbox.
    when /DEQUEUER .+ LOCAL\(.+ delivered: Delivered to the user mailbox/
      add_one(:inbound_delivered)

    # This means that an outbound message (with any number of recipients) has
    # been accepted by another server.
    when /DEQUEUER .+ SMTP\(.+ relayed: relayed via /
      add_one(:outbound_relayed_messages)

    # This is a "throttling" rejection by hotmail/msn.
    when /SMTP-\d+\((hotmail|msn)\.com\) rsp: 550 Your e-mail was rejected for policy reasons/
      add_one(:hotmail_rejection)
      add_one(:hotmail_total)

    # This is a successful delivery to hotmail/msn.
    when /SMTP-\d+\((hotmail|msn)\.com\) rsp: 250\s+\<[^>]+\> Queued mail for delivery/
      add_one(:hotmail_accepted)
      add_one(:hotmail_total)

    # This means a message has been scored by SpamCatcher.  We'll record it as
    # "spam" if its score is 85 or greater (the default 'bostoncollegespam'
    # filter rule).
    when /ADDHEADER "X-SpamCatcher-Score:\s+(\d+)/
      add_one(:messages_spamcatcher_scored)
      score = $1.to_i
      if score > 84
        add_one(:spam_messages)
      elsif score > 77
        add_one(:probably_spam_messages)
      end

    # This means that we've tried to send a message to another host and the
    # message was rejected with a temporary error that used the word
    # 'greylist', implying that we're being greylisted by that MTA.
    when /SMTP-.+ rsp: 4\d\d.+greylist/i
      add_one(:greylisted)

    # This message means an automatic CommuniGate message is being generated
    # (probably a delay or failure warning).
    when /DEQUEUER-.+ generating report message/
      add_one(:report_message_generated)

    # This header will appear when an enqueued message has the header "Mail
    # Delayed" which is an automatically generated message.
    when /header: Subject: (WARNING. Mail Delayed|Message Delayed)/
      add_one(:mail_delayed_warning)

    # This header will appear when a mailbox is corrupted (when the actual
    # info doesn't match the account.info file) and corrections need to be
    # made.
    when /MAILBOX\(.+ Corrected/
      add_one(:corrected_mailbox)

    # This is a 500 error response, meaning that whatever the last command was,
    # it caused a permanent error.  Generally, this means a recipient or a
    # message body was rejected, although it can happen many times within one
    # SMTP session.
    when /SMTPI-.+ rsp: (5\d\d) /
      code = $1.to_i
      if code == 591
        add_one(:messages_rejected)
        add_one(:messages_rejected_spamhaus)
      elsif code == 592 || code == 573 || code == 550
        add_one(:messages_rejected)
        add_one(:messages_rejected_bad_address)
      elsif code == 579
        add_one(:messages_rejected)
        add_one(:messages_rejected_banned_text)
      elsif code == 554
        add_one(:messages_rejected)
        add_one(:messages_rejected_no_address)
      elsif code == 500
        add_one(:messages_rejected)
        add_one(:messages_rejected_quota_full)
      end

    else
      return
    end

    # Write the data out approximately once per half hour.
    @first_scan ||= Time.now
    if (Time.now - @first_scan) > 30.minutes
      write_data 
      @first_scan = Time.now
    end

  end

  def add_one(label)
    @data[@today][label] ||= 0
    @data[@today][label] += 1
  end

  def shut_down
    write_data
  end
end

