-- Create TCP socket that automatically promotes to a COPAS tcp socket
-- when connecting to an endpoint. This means it'll be usable inside
-- a COPAS thread.

local socket = require "socket"
local copas = require "copas"

local wrapped = {}
local copas_org_index
local copasmeta

local function create_wrapped(key)
    return function(self, ...)
	return self.socket[key](self.socket, ...)
    end
end

function wrapped.settimeout(self, timeout)
    self.timeout = timeout
    return 1
end

function wrapped.receive(self, pattern, prefix)
    if self.timeout == 0 then
	local s, err, part = copas.receivePartial(self.socket, pattern)
	if not s and prefix and part then
	    return s, err, prefix .. part
	end
	return s, err, part
    end
    return copas.receive(self.socket, pattern, prefix)
end

function wrapped.connect(self, host, port)
    return copas.connect(self.socket, host, port)
end

local function lookup(self, key)
    local v = wrapped[key]
    if v ~= nil then
	return v
    end
    if type(copas_org_index) == "function" then
	v = copas_org_index(self, key)
    else
	v = copas_org_index[key]
    end
    if type(v) == "function" then
	wrapped[key] = v
    end
    if v ~= nil then
	return v
    end
    v = self.socket[key]
    if type(v) == "function" then
	v = create_wrapped(key)
	wrapped[key] = v
    end
    return v
end

function copas.tcpwrap(skt)
    local wrapped = copas.wrap(skt)
    if not copasmeta then
	copasmeta = {}
	local meta = getmetatable(wrapped)
	for k,v in pairs(meta) do
	    if k ~= "__index" then
		copasmeta[k] = v
	    end
	end
	copas_org_index = meta.__index
	copasmeta.__index = lookup
    end
    setmetatable(wrapped, copasmeta)
    return wrapped
end

-- Wrap TCP socket creation/connection so it works inside COPAS
local function wraptcp()
    local tcpskt, err = socket.tcp()
    if not tcpskt then
	return tcpskt, err
    end
    return copas.tcpwrap(tcpskt)
end

return wraptcp
