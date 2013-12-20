Datastore = require "nedb"
twilio = require "twilio"
twilioConfig = require "./twilio-config"
phoneNumbersConfig = require "./phone-numbers-config"

twilioClient = twilio twilioConfig.accountSid, twilioConfig.authToken

MIN_INTERVAL_MINUTES = 60 # 1 hour

# User database
#   nPhoneNumber: normalized phone #, unique key identifying user
#   uPhoneNumber: the phone # as the user entered it
#   signupTime:   when the user signed up and was added
#   enabled:      boolean, whether we are allowed to send SMSes to this user
#
users = new Datastore {
  filename: "../data/users.nedb",
  autoload: true,
}

users.ensureIndex {
  fieldName: "nPhoneNumber",
  unique: true,
}, (err) ->
  console.error "NeDB constraint (unique phoneNumber) couldn't be added" if err?

# Alerts database
#   nPhoneNumber: the normalized phone number of the subscriber
#   twitchGameId: the Twitch game ID of the game to alert for
#   threshold:    the number of viewers to 
#   enabled:      boolean, whether we should send messages to this
#   onCooldown:   set to true when we fire, reset when below threshold
#   lastFired:    the time we last fired this alert
#   countFired:   the total number of times we've fired this alert
#   createTime:   the time when the alert was created
#
alerts = new Datastore {
  filename: "../data/alerts.nedb",
  autoload: true,
}

alerts.ensureIndex {
  fieldName: "nPhoneNumber",
}, (err) ->
  console.error "NeDB index couldn't be added to alerts" if err?

alerts.ensureIndex {
  fieldName: "twitchGameId",
}, (err) ->
  console.error "NeDB index for twitchGameId on alerts failed" if err?



normalizePhoneNumber = (phoneNumber) ->
  """Takes any phone number and normalizes it for our database"""

  npn = ""
  for c in phoneNumber
    if c in "0123456789+"
      npn += c
  return npn

addUser = (phoneNumber, callback) ->
  """Adds a user with the given phone number to the database"""

  signupTime = Date.now()
  npn = normalizePhoneNumber phoneNumber

  await
    users.insert {
      nPhoneNumber: npn,
      uPhoneNumber: phoneNumber,
      signupTime: signupTime,
      enabled: true,
    }, defer(err, newDoc)

  callback err, newDoc if callback?


findUser = (phoneNumber, callback) ->
  """Finds the user referenced by phone number"""

  npn = normalizePhoneNumber phoneNumber

  await
    users.find {
      nPhoneNumber: npn,
    }, defer(err, docs)

  if err
    callback err, docs if callback?
  else
    #assert (docs.length <= 1), "NeDB problem: There should never be more than one user with the same normalized phone number"
    if docs.length > 0
      callback err, docs[0] if callback?
    else
      callback err, false if callback?

setUserEnabled = (phoneNumber, enabled) ->
  """Turns sending SMSes to user on (true) or off (false)"""

  npn = normalizePhoneNumber phoneNumber
  await
    users.update { nPhoneNumber: npn }, { $set: { enabled: enabled } }, {}, defer(err, numReplaced)
  if err?
    console.error "There was some error updating the enabled state for phone number #{ phoneNumber }"
  if numReplaced < 1
    console.error "Tried to set enabled to #{ enabled } for phone number '#{ phoneNumber }' but couldn't find a matching user"
  else if numReplaced > 1
    console.error "Should never happen"
  else
    # Everything's OK

enableUser = (phoneNumber) ->
  """Enables sending SMSes to a user"""

  setUserEnabled phoneNumber, true

disableUser = (phoneNumber) ->
  """Disables sending SMSes to a user"""

  setUserEnabled phoneNumber, false


createAlert = (phoneNumber, twitchGameId, threshold, callback) ->
  """Creates an alert to SMS a person when a certain game has more than
      a certain number of people watching it"""
  
  npn = normalizePhoneNumber phoneNumber
  newAlert = 
    nPhoneNumber: npn
    twitchGameId: twitchGameId
    threshold: threshold
    enabled: true
    onCooldown: false
    lastFired: null
    createTime: Date.now()

  await
    alerts.update {
        nPhoneNumber: npn,
        twitchGameId: twitchGameId,
      }, newAlert, { upsert: true }, defer(err, numReplaced, upsert)

  console.error "Could not create alert for '#{ phoneNumber }' for #{ twitchGameId }" if err?

  if upsert
    console.log "Updated alert for #{ phoneNumber } for #{ twitchGameId } to #{ threshold }"
  else
    console.log "Created new alert for #{ phoneNumber } for #{ twitchGameId } with threshold #{ threshold }"

  callback err, newAlert, upsert if callback?


deleteAlert = (phoneNumber, twitchGameId, callback) ->
  """Deletes the alert for a given user for a given game"""

  npn = normalizePhoneNumber phoneNumber
  await
    alerts.remove {
      nPhoneNumber: npn,
      twitchGameId: twitchGameId,
    }, { multi: true }, defer(err, numRemoved)

  console.error "Error removing alert for #{ npn } for #{ twitchGameId }" if err?
  callback err, numRemoved if callback?

recordAlertFired = (phoneNumber, twitchGameId, callback) ->
  """Records that an alert has been fired in the database"""

  npn = normalizePhoneNumber phoneNumber

  await
    alerts.update {
      nPhoneNumber: npn,
      twitchGameId: twitchGameId,
    }, { $set: {
      onCooldown: true,
      lastFired: Date.now(),
    }}, {}, defer(err, numReplaced, upsert)

  console.error "Error recording alert fire for #{ npn } for #{ twitchGameId }" if err?
  callback err, numReplaced if callback?

checkShouldAlertFire = (phoneNumber, twitchGameId, currentViewers, callback) ->
  """Calls `callback` with true/false depending on whether the 
      alert should fire and also will reset the cooldown of the alert
      """

  npn = normalizePhoneNumber phoneNumber

  await
    alerts.find {
      nPhoneNumber: npn,
      twitchGameId: twitchGameId,
    }, defer(err, docs)

  console.error "Error checking if alert should fire for #{ phoneNumber } for #{ twitchGameId }" if err?

  if docs.length > 1
    # If there is more than one alert, then this shouldn't happen
    console.error "More than 1 alert for phone number/game pair #{ npn }/#{ twitchGameId }"
    callback true, false
  else if not docs
    callback err, false
  else
    alert = docs[0]
    if not alert.enabled
      # This alert is disabled so we should never fire while like this
      callback err, false, alert

    else if ((Date.now() - alert.lastFired) / 1000) < (60 * MIN_INTERVAL_MINUTES)
      # If the alert has been fired in the last hour, then we 
      # won't fire it
      callback err, false, alert

    else
      if currentViewers >= alert.threshold
        if alert.onCooldown
          # We are above the viewer threshold but we are on cooldown, 
          # so we shouldn't fire
          callback err, false, alert

        else
          # We are above the viewer threshold and we are not on cooldown
          # so we should fire
          callback err, true, alert
      else
        # There aren't enough viewers to fire but if we are on cooldown
        # then we want to turn off cooldown since we've dropped below
        # the threshold
        if alert.onCooldown
          alerts.update {
            nPhoneNumber: npn,
            twitchGameId: twitchGameId,
          }, { $set: {
            onCooldown: false,
          }}, {}, (err, numReplaced, upsert) -> 
            console.error "Couldn't turn off cooldown on alert for #{ npn }/#{ twitchGameId }" if err?

        callback err, false, alert

findAlertsForGame = (twitchGameId, callback) ->
  await
    alerts.find {
      twitchGameId: twitchGameId,
      enabled: true,
    }, defer(err, docs)
  console.error "Error finding all alerts for #{ twitchGameId }" if err?
  callback err, docs if callback?

  
fireAlert = (phoneNumber, game, currentInfo, callback) ->
  s = "#{ game.name } Twitch alert! #{ currentInfo.viewers } ppl are watching #{ currentInfo.channels } channels. twitch://game/#{ encodeURIComponent game.name }"
  await
    sendSms s, [phoneNumber], defer err
  if err
    console.error "Couldn't send SMS to #{ phoneNumber }"
    callback true, phoneNumber, game, currentInfo if callback?
  else
    await
      recordAlertFired phoneNumber, game.twitchGameId, defer err
    console.error "Couldn't record alert" if err?
    callback err, phoneNumber, game, currentInfo if callback?

sendSms = (message, recipients, callback) ->
  """Sends an SMS to a given list of recipients"""

  allOk = true
  await
    for toNumber, i in recipients
      twilioClient.sendMessage {
        to: toNumber,
        from: twilioConfig.number,
        body: message,
      }, (err, responseData) ->
        if err
          console.error "Twilio Error: from=#{ responseData.from } body=#{ responseData.body }"
          allOk = false
        defer()
  if allOk
    callback null, recipients.length, message if callback?
  else
    callback true, recipients.length, message if callback?




_dump = (db) ->
  """Dump the entire database for debugging"""

  await
    db.find {}, defer(err, docs)
  for doc in docs
    console.log(JSON.stringify(docs))

_dumpUsers = () -> _dump users
_dumpAlerts = () -> _dump alerts

module.exports =
  normalizePhoneNumber: normalizePhoneNumber
  addUser: addUser
  findUser: findUser
  setUserEnabled: setUserEnabled
  enableUser: enableUser
  disableUser: disableUser
  createAlert: createAlert
  deleteAlert: deleteAlert
  checkShouldAlertFire: checkShouldAlertFire
  sendSms: sendSms

  _dump: _dump
  _dumpUsers: _dumpUsers
  _dumpAlerts: _dumpAlerts

  __expose:
    users: users
    alerts: alerts

