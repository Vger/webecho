-- Send data to remote (which is parsed by incoming.lua)

local copas = require "copas"
local poster = require "webmeet.poster"
local char = string.char
local concat = table.concat
local encode_uint, construct
local M = {}; M.__index = M

function encode_uint(value)
    local lowvalue = value % 128
    local nextvalue = (value - lowvalue) / 128
    if nextvalue == 0 then
	return char(lowvalue)
    else
	return char(lowvalue + 128) .. encode_uint(nextvalue)
    end
end

function construct(sendimpl)
    if type(sendimpl) == "string" or type(sendimpl) == "table" then
	sendimpl = poster(sendimpl)
    elseif type(sendimpl) ~= "function" then
	return nil, "Not a function specified in construction of webmeet.outgoing"
    end
    local self = setmetatable({
	lowimpl = sendimpl,
	data = {},
    }, M)
    self.sendthread = copas.addthread(function()
	while not self.closed do
	    local senddata
	    repeat
		senddata = concat(self.data)
		if senddata == "" then
		    if self.closed then
			break
		    end
		    copas.sleep(-1)
		end
	    until senddata ~= ""
	    self.data = {}
	    self.lowimpl(senddata)
	end
	self.lowimpl(nil)
    end)
    return self
end

function M:encode(data)
    local datalen = type(data) == "string" and #data or 0
    local encoded = encode_uint(datalen) .. (datalen ~= 0 and data or "")
    return encoded
end

function M:send(data)
    if type(data) ~= "string" or self.closed then
	return
    end
    self.data[#self.data + 1] = self:encode(data)
    copas.wakeup(self.sendthread)
    return true
end

function M:close()
    self.closed = true
    if #self.data == 0 then
	copas.wakeup(self.sendthread)
    end
end

return construct
