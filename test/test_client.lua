local client = require "webmeet.client"
local poster = require "webmeet.poster"
local getter = require "webmeet.getter"
local copas = require "copas"

local postreq = "http://127.0.0.1:8888/clientreq/"
local getreq = "http://127.0.0.1:8888/serverrep/"

local myclient = client(poster(postreq), getter(getreq))

myclient:send("Hello there")
myclient:set_notify(function()
    print(myclient:get())
end)

print("copas loop...")
copas.loop()
