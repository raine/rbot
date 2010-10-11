#-- vim:sw=2:et
#++
#
# :title: mirror plugin for rbot
#
# Author:: Raine Virta <raine.virta@gmail.com>
# Copyright:: (C) 2010 Raine Virta
# License:: GPL v2
#
# Automatically mirrors URLs matching a configurable pattern on the plugin's
# own HTTP server. For that purpose, it requires an open port on the system.
# Files are removed automatically after a certain time unless mirror.expire_in
# is set to 'never'.
#
# TODO configurable channel whitelist
#

require 'mongrel'

# Override Mongrel's DirHandler#process to remove expired files before
# processing a request
unless ::Mongrel::DirHandler.instance_methods.include?("old_process")
  module ::Mongrel
    class DirHandler
      alias :old_process :process

      def process(request, response)
        remove_expired
        old_process(request, response)
      end

      def remove_expired
        time_str = Irc::Utils.bot.config['mirror.expire_in']
        return if time_str == "never"

        begin
          offset = Irc::Utils.parse_time_offset(time_str)
        rescue => e
          error "couldn't parse mirror.expire_in"
          return
        end

        files = Dir["#{@path}/*"]
        files.each do |f|
          File.unlink(f) if Time.now > File.new(f).ctime + offset
        end
      end
    end
  end
end

class MirrorPlugin < Plugin
  OUR_UNSAFE = Regexp.new("[^#{URI::PATTERN::UNRESERVED}#{URI::PATTERN::RESERVED}%# ]", false, 'N')

  Config.register Config::IntegerValue.new('mirror.port',
    :default => 5555, :validate => Proc.new { |v| v > 0 },
    :desc => "Port to use for serving the files",
    :on_change => Proc.new { |bot, v| plg = bot.plugins['mirror']; plg.cleanup; plg.http_start })
  Config.register Config::IntegerValue.new('mirror.max_size',
    :default => 1024, :validate => Proc.new { |v| v > 0 },
    :desc => "Maximum size of files in kilobytes, files larger than this won't be mirrored")
  Config.register Config::ArrayValue.new('mirror.url_patterns',
    :default => ['4chan\.org\/.*\.(?:png|jpg|gif)$'],
    :desc => "A list of regular expressions that URLs should match to be mirrored")
  Config.register Config::StringValue.new('mirror.expire_in',
    :default => "12 hours",
    :desc => "For how long files should be stored, e.g. 2 hours, 1 day, never")
  Config.register Config::StringValue.new('mirror.hostname',
    :desc => "By default, bot's IRC hostname is used in the URLs, this will override it")

  def initialize
    super

    @mirror_path = File.join(@bot.botclass, 'mirror')
    FileUtils.mkdir_p @mirror_path
    http_start
  end

  def help(plugin, topic="")
    "automatically mirror URLs matching a configurable pattern on the plugin's own HTTP server | usage: mirror [url that 404'd or whatever]"
  end

  def cleanup
    @http_server.graceful_shutdown
    @http_server.stop
    super
  end

  def http_start
    @http_server = Mongrel::HttpServer.new("0.0.0.0", @bot.config['mirror.port'])
    @http_server.register("/", Mongrel::DirHandler.new(@mirror_path))
    Thread.new { @http_server.run }
  end

  def message(m)
    return if @bot.config['mirror.url_patterns'].empty?
    # ignore private messages
    return if m.address?

    escaped = URI.escape(m.message, OUR_UNSAFE)
    urls = URI.extract(escaped, ['http', 'https'])
    return if urls.empty?

    Thread.new { handle_urls(m, :urls => urls) }
  end

  def handle_urls(m, opts)
    urls = opts[:urls]
    urls.each do |url|
      patterns = @bot.config['mirror.url_patterns'].map { |e| Regexp.new(e, true) }
      if url =~ Regexp.union(patterns)
        file_name = File.join(@mirror_path, url.split("/")[-1])
        next if File.exist?(file_name)

        head = @bot.httputil.head(url)
        if head.is_a? Net::HTTPOK
          if head['content-length'].to_i / 1024 <= @bot.config['mirror.max_size']
            File.open(file_name, 'w') {|f| f.write(@bot.httputil.get(url)) }
          else
            debug 'file too big'
          end
        end
      end
    end
  end

  def mirror_url(file_name=nil)
    hostname = @bot.config['mirror.hostname'] || @bot.myself.host
    "http://#{hostname}:#{@bot.config['mirror.port']}/#{file_name ? file_name : ''}"
  end

  def url_action(m, params)
    file_name = params[:url].split('/')[-1]
    file_path = File.join(@mirror_path, file_name)

    if File.exist?(file_path)
      m.reply _("it's here! %{url}") % { :url => mirror_url(file_name) }
    else
      m.reply _("don't have it")
    end
  end

  def mirror_action(m, params)
    m.reply mirror_url
  end
end

plugin = MirrorPlugin.new
plugin.map 'mirror :url', :action => 'url_action'
plugin.map 'mirror',      :action => 'mirror_action'
