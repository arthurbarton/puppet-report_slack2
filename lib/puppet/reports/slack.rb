require 'puppet'
require 'puppet/network/http_pool'
require 'net/https'
require 'uri'
require 'json'

Puppet::Reports.register_report(:slack) do
  def process
    configdir = File.dirname(Puppet.settings[:config])
    configfile = File.join(configdir, 'slack.yaml')
    raise(Puppet::ParseError, "Slack report config file #{configfile} not readable") unless File.file?(configfile)

    @config = YAML.load_file(configfile)

    @config["statuses"] ||= "changed,failed"
    statuses = @config["statuses"].split(",")

    # Kernel#` should always run on puppetserver host
    puppetmaster_hostname = `hostname`.chomp
    pretxt = "Puppet status: *%s*" % self.status
    message = <<-FORMAT % [puppetmaster_hostname, self.host, self.environment]
```
Puppet Master Host = %s
Provisioned Host   = %s
Run Environment    = %s
```
    FORMAT
    message.strip!
    color = nil

    if statuses.include?(self.status)
      case self.status
      when "changed"
        pretxt = ":congratulations: #{pretxt}"
        color = 'good'
      when "failed"
        pretxt = ":warning: #{pretxt}"
        color = 'warning'
      when "unchanged"
        pretxt = ":zzz: #{pretxt}"
        color = '#cccccc'
      else
        pretxt = ":grey_question: #{pretxt}"
        color = 'warning'
      end

      payload = make_payload(pretxt, message, color)

      @config["channels"].each do |channel|
        channel.gsub!(/^\\/, '')
        _payload = payload.merge("channel" => channel)
        post_to_webhook(URI.parse(@config["webhook"]), _payload)
        Puppet.notice("Notification sent to slack channel: #{channel}")
      end
    end
  end

  private
  def make_payload(pretxt, message, color)
    {
      "username" => (@config["username"] || "puppet"),
      "icon_url" => (@config["icon_url"] || "https://cloud.githubusercontent.com/assets/91011/6860448/96c424a0-d46b-11e4-9131-31a711893171.png"),
      "attachments" => [{
          "pretext" => pretxt,
          "text"    => message,
          "mrkdwn_in" => [:text, :pretext],
          "color"   => color,
        }],
    }
  end

  def post_to_webhook(uri, payload)
    https = Net::HTTP.new(uri.host, 443)
    https.use_ssl = true
    r = https.start do |https|
      https.post(uri.path, payload.to_json)
    end
    case r
    when Net::HTTPSuccess
      return
    else
      Puppet.err("Notification sent faild to slack channel: #{channel}")
    end
  end
end
