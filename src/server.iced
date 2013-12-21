#!/usr/bin/env iced

twitchScanner = require "./twitch-scanner"
model = require "./model"

console.log "required libs successfully."

scannerInterval = setInterval(() ->
    console.log "Examining the top games on Twitch at #{ Date.now() }"
    twitchScanner.checkTopGames()
  , 1000 * 5)

console.log "interval set."
