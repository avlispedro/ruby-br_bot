#-- vim:sw=2:et
#++
#
# :title: Fortune plugin

class FortunePlugin < Plugin
  Config.register Config::StringValue.new('fortune.path',
    :default => '',
    :desc => "Full path to the fortune executable")

  def help(plugin, topic="")
    "fortune [<category>] => get a (short) fortune, optionally specifying fortune category || fortune categories => show categories"
  end

  def find_fortune
    fortune = @bot.config['fortune.path']
    return fortune if fortune

    ["/usr/bin/fortune",
     "/usr/share/bin/fortune",
     "/usr/games/fortune",
     "/usr/local/games/fortune",
     "/usr/local/bin/fortune"].each do |f|
      if FileTest.executable? f
        fortune = f
        break
      end
    end

    return nil unless fortune
      
    # Try setting the config entry
    config_par = {:key => 'fortune.path', :value => [fortune], :silent => true }
    debug "Setting fortune.path to #{fortune}"
    set_path = @bot.plugins['config'].handle_set(m, config_par)
    if set_path
      debug "fortune.path set to #{@bot.config['fortune.path']}"
    else
      debug "couldn't set fortune.path"
    end

    return fortune
  end

  ## Pick a fortune
  def fortune(m, params)
    db = params[:db]
    fortune = find_fortune
    m.reply "fortune executable not found (try setting the 'fortune.path' variable)" unless fortune

    begin
      ret = Utils.safe_exec(fortune, "-n", "350", "-s", db)

      ## cleanup ret
      ret = ret.split(/\n+/).map do |l|
        # check if this is a "  -- Some Dood" line
        if l =~ /^\s+-{1,3}\s+\w/
          # turn "-" into "--"
          l.gsub!(/^\s+-\s/, '-- ')
          # extra space
          " " + l.strip
        else
          # just remove leading and trailing whitespace
          l.strip
        end
      end.join(" ")

    rescue
      ret = "failed to execute fortune"
      # TODO reset fortune.path when execution fails
    end

    m.reply ret
  end

  # Print the fortune categories
  def categories(m, params)
    fortune = find_fortune
    m.reply "fortune executable not found (try setting the 'fortune.path' variable)" unless fortune

    ## list all fortune databases
    categories = Utils.safe_exec(fortune, "-f").split(/\n+ */).map{ |f|
      f.split[1]
    }.select{ |f|
      f[0..0] != '/'
    }.sort

    ## say 'em!
    m.reply "Fortune categories: #{categories.join ', '}"
  end
 
end
plugin = FortunePlugin.new
plugin.map 'fortune categories', :action => "categories"
plugin.map 'fortune list', :action => "categories"
plugin.map 'fortune :db', :defaults => {:db => ''},
                          :requirements => {:db => /^[^-][\w-]+$/}
