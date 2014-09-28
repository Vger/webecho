local queue = require "webmeet.queue"
local incoming = require "webmeet.incoming"
local outgoing = require "webmeet.outgoing"

local M = {}; M.__index = M
local construct

function construct(outgoing_lowimpl, incoming_lowimpl, strict)
    local self = setmetatable({
	strict = strict,
	lastreq = 0,
	requests = queue(),
    }, M)
    self.incoming = incoming(self.requests)
    self.outgoing = outgoing(outgoing_lowimpl)
    incoming_lowimpl(self.incoming)
    return self
end

local function process_get(self, ...)
    local req, reqid = ...
    if req and reqid then
	if not self.lastreq or reqid == self.lastreq+1 then
	    self.lastreq = reqid
	elseif self.strict then
	    if reqid < self.lastreq then
		self:reply(reqid, nil, "Too low request id")
	    else
		-- Put back the request since it's not the request id we expected.
		self.requests(reqid, data)
	    end
	    return nil
	end
    end
    return ...
end

-- Get next incoming request
function M:get()
    return process_get(self, self.requests:get())
end

-- Reply to request
function M:reply(reqid, result, err)
    if result then
	local restype = type(result)
	if restype ~= "number" and restype ~= "string" then
	    result = ""
	end
	self.outgoing(reqid, "S" .. result)
	return
    end
    if err then
	local errtype = type(err)
	if errtype ~= "number" and errtype ~= "string" then
	    err = ""
	end
	self.outgoing(reqid, "E" .. err)
	return
    end
    if reqid == self.lastreq and reqid then
	-- Accumulated ack
	self.outgoing(reqid, "S")
    end
end

-- Notify callback when there's request activity
function M:set_notify(notify)
    self.requests:set_notify(notify)
end

return construct
