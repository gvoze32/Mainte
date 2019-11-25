#!/bin/env sh

killall conky

#conky -c $HOME/.config/conky/conkyrc-dark-bspwm &
conky -c $HOME/.conky/Mainte/conkyrc-dark-bspwm &
sleep 0.8
#conky -c $HOME/.config/conky/conkyrc-dark-bg &
conky -c $HOME/.conky/Mainte/conkyrc-dark-bg &
