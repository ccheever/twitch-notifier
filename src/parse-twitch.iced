http = require "http"
twilio = require "twilio"
twilioConfig = require "./twilio-config"
phoneNumbersConfig = require "./phone-numbers-config"


# Max limit is 100 it seems; for now that's sufficient
TWITCH_TOP_GAMES_DATA_URL = "http://api.twitch.tv/kraken/games/top?limit=100&offset=0&on_site=1"
TWITCH_SC2_LIVE_STREAMS_DATA_URL = "http://api.twitch.tv/kraken/streams?limit=24&offset=0&game=StarCraft+II%3A+Heart+of+the+Swarm&on_site=1"
SC2_GIANTBOMB_ID = 24078
SC2_TWITCH_ID = 21818

# Dan Tran #: 714-270-8334

twilioClient = twilio twilioConfig.accountSid, twilioConfig.authToken

sendSms = (message, recipients) ->
  for toNumber in recipients
    twilioClient.sendMessage {
      to: toNumber,
      from: twilioConfig.number,
      body: message,
    }, (err, responseData) ->
      if err
        console.error "Twilio Error: from=#{ responseData.from } body=#{ responseData.body }"


parseTopGames = (url) ->
  if !url?
    url = TWITCH_TOP_GAMES_DATA_URL
  await 
    http.get url, defer response

  body = ""
  await
    response.on "data", (chunk) ->
      body += chunk
    response.on "end", defer()

  data = JSON.parse body
  top = data.top
  for info in top
    viewers = info.viewers
    channels = info.channels
    gameId = info.game._id
    giantbombId = info.game.giantbomb_id
    gameName = info.game.name
    #console.log "#{ viewers } people are watching #{ gameName } on #{ channels } channels."
    if gameId == SC2_TWITCH_ID
      sc2Alert viewers, channels, info.game
      break


  __expose.response = response
  __expose.body = body
  __expose.data = data
  #console.log "done."

sc2Alert = (viewers, channels, game) ->
  s = "#{ game.name } Twitch alert! #{ viewers } ppl are watching on #{ channels } channels. twitch://game/#{ encodeURIComponent game.name }"
  console.log s

  # Send an SMS
  sendSms s, [phoneNumbersConfig.CharlieCheever]
 


__expose = {}

module.exports =
  parseTopGames: parseTopGames
  __expose: __expose
