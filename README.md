**ifboot** is an IRC bot that allows interactive fiction games to be played
by multiple people at the same time.

It runs Frotz in a tmux instance, and it feeds commands that users input into
tmux and sends messages with the output from Frotz.

To fulfull all dependencies on Arch:

    gem install cinch cinch-identify
    pacman -S tmux
    pacaur -S frotz

There is currently a lot of stuff that's hardcoded, so you may need to modify
the source code of ifboot.rb in order to change some things.
