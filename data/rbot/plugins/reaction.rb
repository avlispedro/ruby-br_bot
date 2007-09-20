#-- vim:sw=2:et
#++
#
# :title: Reaction plugin
#
# Author:: Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2007 Giuseppe Bilotta
# License:: GPLv2
#
# Build one-liner replies/reactions to expressions/actions in channel
#
# Very alpha stage, so beware of sudden reaction syntax changes

class ::Reaction
  attr_reader :trigger, :replies
  attr_reader :raw_trigger, :raw_replies
  attr_accessor :author, :date, :channel

  class ::Reply
    attr_accessor :act, :reply, :pct, :range
    def initialize(act, expr, pct, range=nil)
      @act = act
      @reply = expr
      @pct = pct
      @range = range
    end

    def to_s
      "#{act} #{reply} #{pct}" + ( @range ? " (#{@range})" : "")
    end

    def apply(subs={})
      [act, reply % subs]
    end
  end

  def trigger=(expr)
    @raw_trigger = expr.dup
    act = false
    rex = expr.dup
    if rex.sub!(/^act:/,'')
      act = true
    end
    @trigger = [act]
    if rex.sub!(%r@^([/!])(.*)\1$@, '\2')
      @trigger << Regexp.new(rex)
    else
      @trigger << Regexp.new(/\b#{Regexp.escape(rex)}\b/u)
    end
  end

  def add_reply(expr, pct)
    @raw_replies << expr.dup
    act = false
    rex = expr.dup
    if rex.sub!(/^act:/,'')
      act = true
    end
    @replies << Reply.new(act ? :act : :reply, rex, pct)
    make_ranges
  end

  def make_ranges
    totals = 0
    pcts = @replies.map { |rep|
      totals += rep.pct
      rep.pct
    }
    pcts.map! { |p|
      p/totals
    } if totals > 1
    debug "percentages: #{pcts.inspect}"

    last = 0
    @replies.each_with_index { |r, i|
      p = pcts[i]
      r.range = last..(last+p)
      last+=p
    }
    debug "ranges: #{@replies.map { |r| r.range}.inspect}"
  end

  def pick_reply
    pick = rand()
    debug "#{pick} in #{@replies.map { |r| r.range}.inspect}"
    @replies.each { |r|
      return r if r.range and r.range === pick
    }
    return nil
  end

  def ===(message)
    return nil if @trigger.first and not message.action
    return message.message.match(@trigger.last)
  end

  def initialize(trig, auth, dt, chan)
    self.trigger=trig
    self.author=auth.to_s
    self.date=dt
    self.channel=chan.to_s
    @raw_replies = []
    @replies = []
  end

  def to_s
    "trigger #{raw_trigger} (#{author}, #{channel}, #{date})"
  end

end

class ReactionPlugin < Plugin

  ADD_SYNTAX = 'react to *trigger with *reply at :chance chance'

  def add_syntax
    return ADD_SYNTAX
  end

  attr :reactions

  def initialize
    super
    if @registry.has_key?(:reactions)
      @reactions = @registry[:reactions]
      raise unless @reactions
    else
      @reactions = []
    end

    @subs = {
      :bold => Bold,
      :underline => Underline,
      :reverse => Reverse,
      :italic => Italic,
      :normal => NormalText,
      :color => Color,
      :colour => Color,
      :bot => @bot.myself,
    }.merge ColorCode
  end

  def save
    @registry[:reactions] = @reactions
  end

  def help(plugin, topic="")
    if plugin.to_sym == :react
      return "react to <trigger> with <reply> [at <chance> chance] => " +
      "create a new reaction to expression <trigger> to which the bot will reply <reply>, optionally at chance <chance>, " +
      "seek help for reaction trigger, reaction reply and reaction chance for more details"
    end
    case (topic.to_sym rescue nil)
    when :remove, :delete, :rm, :del
      "reaction #{topic} <trigger> => removes the reaction to expression <trigger>"
    when :chance, :chances
      "reaction chances are expressed either in terms of percentage (like 30%) or in terms of floating point numbers (like 0.3), and are clipped to be " +
      "between 0 and 1 (i.e. 0% and 100%). A reaction can have multiple replies, each with a different chance; if the total of the chances is less than one, " +
      "there is a chance that the trigger will not actually cause a reply. Otherwise, the chances express the relative frequency of the replies."
    when :trigger, :triggers
      "reaction triggers can have one of the format: single_word 'multiple words' \"multiple words \" /regular_expression/ !regular_expression!. " + 
      "If prefixed by 'act:' (e.g. act:/(order|command)s/) the bot will only respond if a CTCP ACTION matches the trigger"
    when :reply, :replies
      "reaction replies are simply messages that the bot will reply when a trigger is matched. " +
      "Replies can be prefixed by 'act:' (e.g. act:goes shopping) to signify that the bot should act instead of saying the message. " +
      "Replies can use the %%{key} syntax to access one of the following keys: " +
      "who (the user that said the trigger), bot (the bot's own nick), " +
      "target (the first word following the trigger), what (whatever follows target), " +
      "stuff (everything that follows the trigger), match (the actual matched text)"
    when :list
      "reaction list [n]: lists the n-the page of programmed reactions (30 reactions are listed per page)"
    else
      "reaction topics: add, remove, delete, rm, del, triggers, replies, list"
    end
  end

  def unreplied(m)
    return unless PrivMessage === m
    debug "testing #{m} for reactions"
    return if @reactions.empty?
    wanted = @reactions.find { |react|
      react === m
    }
    return unless wanted
    match = wanted === m
    matched = match[0]
    stuff = match.post_match.strip
    target, what = stuff.split(/\s+/, 2)
    extra = {
      :who => m.sourcenick,
      :match => matched,
      :target => target,
      :what => what,
      :stuff => stuff
    }
    subs = @subs.dup.merge extra
    reply = wanted.pick_reply
    debug "picked #{reply}"
    return unless reply
    args = reply.apply(subs)
    m.__send__(*args)
  end

  def find_reaction(trigger)
    @reactions.find { |react|
      react.raw_trigger == trigger
    }
  end

  def handle_add(m, params)
    trigger = params[:trigger].to_s
    reply = params[:reply].to_s

    pct = params[:chance] || "1"
    if pct.sub(/%$/,'')
      pct = (pct.to_f/100).clip(0,1)
    else
      pct = pct.to_f.clip(0,1)
    end

    reaction = find_reaction(trigger)
    if not reaction
      reaction = Reaction.new(trigger, m.sourcenick, Time.now, m.channel)
      @reactions << reaction
      m.reply "Ok, I'll start reacting to #{reaction.raw_trigger}"
    end
    reaction.add_reply(reply, pct)
    m.reply "I'll react to #{reaction.raw_trigger} with #{reaction.raw_replies.last} (#{(reaction.replies.last.pct * 100).to_i}%)"
  end

  def handle_rm(m, params)
    trigger = params[:trigger].to_s
    debug trigger.inspect
    found = find_reaction(trigger)
    if found
      @reactions.delete(found)
      m.reply "I won't react to #{found.raw_trigger} anymore"
    else
      m.reply "no reaction programmed for #{trigger}"
    end
  end

  def handle_list(m, params)
    if @reactions.empty?
      m.reply "no reactions programmed"
      return
    end

    per_page = 30
    pages = @reactions.length / per_page + 1
    page = params[:page].to_i.clip(1, pages)

    str = @reactions[(page-1)*per_page, per_page].join(", ")

    m.reply "Programmed reactions (page #{page}/#{pages}): #{str}"
  end

end

plugin = ReactionPlugin.new

plugin.map plugin.add_syntax, :action => 'handle_add',
  :requirements => { :trigger => /^(?:act:)?!.*?!/ }
plugin.map plugin.add_syntax, :action => 'handle_add',
  :requirements => { :trigger => /^(?:act:)?\/.*?\// }
plugin.map plugin.add_syntax, :action => 'handle_add',
  :requirements => { :trigger => /^(?:act:)?".*?"/ }
plugin.map plugin.add_syntax, :action => 'handle_add',
  :requirements => { :trigger => /^(?:act:)?'.*?'/ }
plugin.map plugin.add_syntax.sub('*', ':'), :action => 'handle_add'

plugin.map 'reaction list [:page]', :action => 'handle_list',
  :requirements => { :page => /^\d+$/ }

plugin.map 'reaction del[ete] *trigger', :action => 'handle_rm'
plugin.map 'reaction delete *trigger', :action => 'handle_rm'
plugin.map 'reaction remove *trigger', :action => 'handle_rm'
plugin.map 'reaction rm *trigger', :action => 'handle_rm'