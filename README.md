twitch-notifier
===============

Notify me when popular events are going on on Twitch

Notes:
    To run this, you need to include a .js module for the Twilio API config
    in the lib/ directory. It should look something like this:


module.exports = {
  accountSid: "<Your account SID>",
  authToken: "<Your auth token>",
  number: "<Your Twilio phone number to send from>", // +1 650-353-3368
}
