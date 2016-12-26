#!/usr/bin/ruby

require 'cinch'
require 'cinch/logger'
require 'cinch/plugins/identify'

require_relative 'config.rb'

# a bunch of ugly hacks...
$config[:logfile] = File.open($config[:logfile], 'a+')
$allow = true

module Cinch
    class Logger
        class NotALogger < Logger
            def log *; end
            def outgoing m
                $allow = true if m =~ /^PRIVMSG .* :>$/
            end
        end
    end
end

def logf txt
    $config[:logfile].puts txt
    $config[:logfile].flush  # FOR DEBUGGING ONLY!!!!!
end

def reply m, txt, suppress_ping=false
    # if txt.length > 800
    #     m.reply 'Max message length (800) reached. Truncated response shown below:'
    #     txt = txt[0..800]
    # end
    txt = "#{m.user.nick}: " + txt unless suppress_ping
    logf "[#{m.time}] <#{$config[:nick]}> #{txt}"
    m.reply txt
end

def frotzflush m
    $allow = false
    sleep 0.05 until File.size? 'frotzbuf'
    data = File.read 'frotzbuf'
    data.sub! /\0*[^\n]*\n/, ''
    # p data
    reply m, data
    File.truncate 'frotzbuf', 0
end

games = {
    zork: 'games/zork/DATA/ZORK1.DAT',
    pig: 'games/LostPig.z8',
    child: 'games/ChildsPlay.zblorb'
}

def playing?
    `tmux ls -F '#S'`.lines.map(&:chomp).include? 'ifboot'
end

tailpid = nil
cmds = {
    help: ->m, args {
        reply m, 'use .foo to send text to Frotz and ..foo to send a command to the bot; use ..commands to get a list of commands'
    },
    commands: ->m, args {
        reply m, "list of commands: #{cmds.keys.map(&:to_s) * ', '}"
    },
    games: ->m, args {
        reply m, "list of games: #{games.keys.map(&:to_s) * ', '}"
    },
    start: ->m, args {
        if playing?
            reply m, 'there is already a game in progress'
        elsif games[args.to_sym]
            `tmux new-session -d -s ifboot 'frotz -S 0 #{games[args.to_sym]}'`
            `tmux send-keys -t ifboot SCRIPT`
            `tmux send-keys -t ifboot Enter`
            `tmux send-keys -t ifboot frotzscript`
            `tmux send-keys -t ifboot Enter`
            sleep 0.05 until File.exist? 'frotzscript'
            tailpid = `tail -f frotzscript > frotzbuf & echo $!`
            frotzflush m
        else
            reply m, "game `#{args}' not found"
        end
    },
    stop: ->m, args {
        if playing?
            `tmux kill-session -t ifboot`
            `rm frotzscript frotzbuf`
            `kill #{tailpid}`
            reply m, 'stopped current game'
        else
            reply m, 'there is no game currently in progress'
        end
    }
}

bot = Cinch::Bot.new do
    prefix = '.'
    botprefix = '.'

    configure do |c|
        c.server = $config[:server]
        c.nick = $config[:nick]
        c.channels = []
        c.plugins.plugins = [Cinch::Plugins::Identify]
        c.plugins.options[Cinch::Plugins::Identify] = {
            username: $config[:nick],
            password: $config[:password],
            type: :nickserv
        }
    end

    on :message, /(.*)/ do |m, txt|
        fmt_msg = "[#{m.time}] <#{m.user.nick}> #{txt}"
        logf fmt_msg
        if txt[0...prefix.length] == prefix
            txt = txt[prefix.length..-1]
            cmd, args = txt.split ' ', 2
        end
        if cmd == botprefix + 'restart'  # special-case
            if m.user.nick == 'KeyboardFire'
                reply m, 'restarting bot...'
                bot.quit("restarting (restarted by #{m.user.nick})")
                sleep 0.1 while bot.quitting
                # you're supposed to run this in a loop
                # while :; do ./ifboot.rb; done
            else
                reply m, 'only KeyboardFire can do that'
            end
        end
        unless cmd.nil?
            if cmd[0...botprefix.length] == botprefix
                cmd = cmd[botprefix.length..-1]
                if cmds[cmd.to_sym]
                    cmds[cmd.to_sym][m, args]
                end
            else
                if playing?
                    if $allow
                        if txt !~ /[^A-Za-z0-9 ]/
                            `tmux send-keys -t ifboot -l '#{txt}'`
                            `tmux send-keys -t ifboot Enter`
                            frotzflush m
                        else
                            reply m, 'alphanumeric input only pls'
                        end
                    end
                else
                    reply m, 'there is no game currently in progress'
                end
            end
        end
    end

    on :notice do |m|
        if m.message.index 'You are now identified for'
            $config[:channels].each do |c|
                bot.join c
            end
        end
    end

    on :nick do |m|
        old, new = m.raw.match(/^:([^!]+)!/)[1], m.user.nick
        logf "[#{m.time}] -!- #{old} is now known as #{new}"
    end

    on :join do |m|
        logf "[#{m.time}] -!- #{m.user.nick} has joined"
        if m.user.nick == $config[:nick]
            reply m, 'Bot started.', true
        else
            reply m, 'welcome! I am a robit, beep boop. Type ..help to get ' +
                'assistance on how to use me.'
        end
    end

    on :leaving do |m|
        fmt_msg = if m.params.length == 3
            "[#{m.time}] -!- #{m.user.nick} was kicked from #{m.params[0]} " +
                "by #{m.params[1]} (#{m.params[2]})"
        else
            "[#{m.time}] -!- #{m.user.nick} has left (#{m.params[0]})"
        end
        logf fmt_msg
    end
end

bot.loggers << Cinch::Logger::NotALogger.new(File.open '/dev/null')
bot.start
