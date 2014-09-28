-- Create TCP socket that automatically promotes to a COPAS tcp socket
-- when connecting to an endpoint. This means it'll be usable inside
-- a COPAS thread.

local socket = require "socket"
local copas = require "copas"

do
    local copasmeta

    local function tcpreceive(self, pattern, prefix)
	if (self.timeout==0) then
	    local s, err, part = copas.receivePartial(self.socket, pattern)
	    if not s and prefix and part then
		return s, err, prefix .. part
	    end
	    return s, err, part
	end
	return copas.receive(self.socket, pattern, prefix)
    end

    function copas.tcpwrap(skt)
	if not copasmeta then
	    local meta = getmetatable(copas.wrap(skt))
	    copasmeta = {}
	    for k,v in pairs(meta) do
		copasmeta[k] = v
	    end
	    copasmeta.__index.receive = tcpreceive
	end
	return setmetatable({socket = skt}, copasmeta)
    end
end

local wrapped_connect
do
    local function handle_connect(self, ...)
	self.wrapped = copas.tcpwrap(self.skt)
	self.skt:settimeout(0)
	return ...
    end

    function wrapped_connect(self, ...)
	return handle_connect(self, self.skt:connect(...))
    end
end

local meta = {}

meta.copasmeth = {}
meta.plainmeth = {}

local function create_method(src, key)
    if src == 'copasmeth' then
	return function(self, ...)
	    return self.wrapped[key](self.wrapped, ...)
	end
    elseif src == 'plainmeth' then
	return function(self, ...)
	    return self.skt[key](self.skt, ...)
	end
    end
end

function meta:__index(key)
    if key == "connect" then
	return wrapped_connect
    elseif key == "wrapped" or key == "skt" then
	return
    end
    local value = self.wrapped and self.wrapped[key]
    local src = 'copasmeth'
    if value == nil then
	value = self.skt and self.skt[key]
	src = 'plainmeth'
    end
    if type(value) ~= 'function' then
	return value
    end
    local cachemeth = meta[src]
    local wrapmeth = cachemeth[key]
    if not wrapmeth then
	wrapmeth = create_method(src, key)
	cachemeth[key] = wrapmeth
    end
    return wrapmeth
end

-- Wrap TCP socket creation/connection so it works inside COPAS
local function wraptcp()
    local tcpskt, err = socket.tcp()
    if not tcpskt then
	return tcpskt, err
    end
    return setmetatable({ skt = tcpskt }, meta)
end

return wraptcp
