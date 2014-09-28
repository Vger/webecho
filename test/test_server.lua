local server = require "webmeet.server"
local poster = require "webmeet.poster"
local getter = require "webmeet.getter"
local copas = require "copas"

local getrequest = "http://127.0.0.1:8888/clientreq/"
local postreply = "http://127.0.0.1:8888/serverrep/"

local myserver = server(poster(postreply), getter(getrequest))

myserver:set_notify(function()
    local data, id = myserver:get()
    print(data, id)
    if data then
	myserver:reply(id, "Hi")
    end
end)

copas.loop()
