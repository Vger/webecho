local publish = require "webmeet.outgoing"
local subscribe = require "webmeet.incoming"
local copas = require "copas"

local postreq = "http://127.0.0.1:8888/clientreq/"
local getreq = "http://127.0.0.1:8888/serverrep/"

local myclient = publish(postreq)
local serverreply = subscribe(getreq)
local gotreply = false

local function main()
    print(serverreply:recv(true))
    gotreply = true
    print(serverreply:recv(true))
    serverreply:close()
    myclient:close()
end

local mainthread = copas.addthread(main)

copas.addthread(function()
    assert(myclient:send("Hello there"))
    copas.sleep(0.5)
    if not gotreply then
	print("Resending")
	assert(myclient:send("Hello there"))
    end
end)

while coroutine.status(mainthread) ~= "dead" do
    copas.step()
end
