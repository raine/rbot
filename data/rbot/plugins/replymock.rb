#-- vim:sw=2:et
#++
#
# :title: Replymock plugin for rbot
#
# Author:: Raine Virta <raine.virta@gmail.com>
# Copyright:: (C) 2010 Raine Virta
# License:: GPL v2
#

class ReplymockPlugin < Plugin
  PATTERNS = {
    "%B" => Bold,
    "%R" => Reverse,
    "%U" => Underline,
    "%I" => Italic,
    "%N" => NormalText
  }

  def help(plugin, topic="")
    _("replymock plugin — helps you mock formatted bot replies, example: `replymock %B%redyellowtest")
  end

  def reply(m, params)
    reply_str = params[:str].to_s

    PATTERNS.each do |a,b|
      reply_str.gsub!(a,b)
    end

    colors = ColorCode.keys.map(&:to_s)
    reply_str.gsub!(/(?:%(#{colors.join("|")}){1,2})/) do |c|
       Irc.color(*$&.tr('%','').scan(Regexp.union(colors)).map(&:to_sym))
    end

    m.reply reply_str
  end
end

plugin = ReplymockPlugin.new
plugin.map "replymock *str", :action => 'reply'
