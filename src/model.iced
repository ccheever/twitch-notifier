Datastore = require "nedb"

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


createAlert = (phoneNumber, twitchGameId, threshold) ->
  npn = normalizePhoneNumber phoneNumber




_dump = () ->
  """Dump the entire database for debugging"""

  await
    users.find {}, defer(err, docs)
  for doc in docs
    console.log(JSON.stringify(docs))


module.exports =
  normalizePhoneNumber: normalizePhoneNumber
  addUser: addUser
  findUser: findUser
  setUserEnabled: setUserEnabled
  enableUser: enableUser
  disableUser: disableUser

  _dump: _dump
  __expose:
    users: users
    alerts: alerts

