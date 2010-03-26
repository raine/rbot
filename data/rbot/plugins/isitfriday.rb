class IsItFridayPlugin < Plugin
  def isitfriday(m, params)
    if friday?
      m.reply "yes!"
    else
      m.reply "no :("
    end
  end

  def friday?
    Time.now.wday == 5
  end 
end

plugin = IsItFridayPlugin.new
plugin.map 'isitfriday', :action => 'isitfriday'
