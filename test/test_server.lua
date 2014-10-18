local sub = require "webmeet.incoming"
local pub = require "webmeet.outgoing"
local copas = require "copas"

local getrequest = "http://127.0.0.1:8888/clientreq/"
local postreply = "http://127.0.0.1:8888/serverrep/"

local myserver = sub(getrequest)
local myreply = pub(postreply)
local mainloop

function mainloop()
    local data = myserver:recv(true)
    print(os.date(), "Got data from client: ", data)
    if data then
	assert(myreply:send("Hi"))
	assert(myreply:send("Again"))
    end
    return mainloop()
end

copas.addthread(mainloop)
copas.loop()
