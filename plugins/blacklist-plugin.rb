#!/usr/bin/ruby

class BlacklistPlugin < CGMonitor::Plugin
  def start_up
    @blacklists_seen = Hash.new
    @messages = Array.new
    my_options[:max_blacklists_per_domain] ||= 4
    my_options[:keep_blacklists_for] ||= 6.hours
    my_options[:time_between_warnings] ||= 30.minutes
    info_message("BlacklistPlugin will look for #{my_options[:max_blacklists_per_domain]} blacklists per domain within #{my_options[:keep_blacklists_for] / 60} minutes (#{my_options[:keep_blacklists_for]} seconds) and report every #{my_options[:time_between_warnings] / 60} minutes (#{my_options[:time_between_warnings]} seconds).")
  end

  def signal
    info_message("BlacklistPlugin will look for #{my_options[:max_blacklists_per_domain]} blacklists per domain within #{my_options[:keep_blacklists_for] / 60} minutes (#{my_options[:keep_blacklists_for]} seconds) and report every #{my_options[:time_between_warnings] / 60} minutes (#{my_options[:time_between_warnings]} seconds).")
  end

  def every_line(line)
    return unless line =~ /SMTP-\d+\(([^\)]+)\).*(rsp|got):\s?[45]\d\d.*(blacklist|blocked|blocklist)/i
    domain = $1;

    # Clean out old blacklists.
    deleted = 0
    total = 0
    @blacklists_seen.each_key do |a_domain|
      @blacklists_seen[a_domain].each do |a_blacklist|
        if (Time.now - a_blacklist[:when]) > my_options[:keep_blacklists_for]
          @blacklists_seen[a_domain].delete(a_blacklist)
          @blacklists_seen.delete(a_domain) if @blacklists_seen[a_domain].empty?
          deleted += 1
        else
          total += 1
        end
      end
    end
    info_message("Deleted #{deleted} blacklist lines from memory. There are now #{total} lines stored in #{@blacklists_seen.size} domains.")

    @blacklists_seen[domain] = Array.new unless @blacklists_seen[domain]
    @blacklists_seen[domain] << { :line => line, :when => Time.now }
    info_message("I saw a new line that looked like a blacklist by the domain '#{domain}': #{line}")

    return unless @blacklists_seen[domain].size > my_options[:max_blacklists_per_domain]
    message = "I saw some lines that looked like a blacklist by the domain '#{domain}':\n  * #{(@blacklists_seen[domain].collect {|b| b[:line]}).join("\n  * ")}" 
    @blacklists_seen.delete(domain)

    warning_message(message)
    send_email_buffered(message, my_options[:time_between_warnings])
  end
end
