local queue = require "webmeet.queue"
local incoming = require "webmeet.incoming"
local outgoing = require "webmeet.outgoing"

local M = {}; M.__index = M
local construct

function construct(outgoing_lowimpl, incoming_lowimpl)
    local self = setmetatable({
	resend = {},
	lastack = 0,
	lastsent = 0,
	replies = queue(),
    }, M)
    self.incoming = incoming(self.replies)
    self.outgoing = outgoing(outgoing_lowimpl)
    incoming_lowimpl(self.incoming)
    return self
end

function M:send(data)
    if type(data) == "string" then
	self.lastsent = self.lastsent + 1
	self.outgoing(self.lastsent, data)
	self.resend[self.lastsent] = data
    end
end

-- Get incoming (accumulated) reply
function M:get()
    local reply, id = self.replies:get()
    if not reply or not id then
	return
    end
    local lastack = self.lastack
    if id > lastack then
	for i = lastack, id do
	    self.resend[i] = nil
	end
	self.lastack = id
    end
    local code = reply:sub(1,1)
    if reply:sub(1, 1) == "E" then
	return nil, reply:sub(2), id
    elseif reply:sub(1, 1) == "S" then
	return reply:sub(2), id
    end
end

-- Re-send outstanding requests
function M:resend()
    for i = self.lastack+1, self.lastsent do
	local data = self.resend[i]
	if type(data) == "string" then
	    self.outgoing(i, data)
	end
    end
end

-- Notify callback when there's reply activity
function M:set_notify(notify)
    self.replies:set_notify(notify)
end

return construct
