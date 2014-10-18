-- Create a sink that parses data from remote and saves it until
-- requested.

local copas = require "copas"
local getter = require "webmeet.getter"
local concat = table.concat
local byte = string.byte
local decode_uint, construct
local M = {}; M.__index = M

function decode_uint(str, startpos)
    local value = byte(str, startpos)
    if value then
	if value < 128 then
	    return value, startpos
	end
	local nextvalue, endpos = decode_uint(str, startpos+1)
	if nextvalue then
	    return value - 128 + 128 * nextvalue, endpos
	end
    end
end

function construct(recvimpl)
    if type(recvimpl) == "string" or type(recvimpl) == "table" then
	recvimpl = getter(recvimpl)
    elseif type(recvimpl) ~= "function" then
	return nil, "Not a function specified in construction of webmeet.incoming"
    end
    local self = setmetatable({
	lowimpl = recvimpl,
	state = "DATA#",
	acc = "",
	lastpos = 0,
	blocks = {}
    }, M)
    recvimpl(self)
    return self
end

function M:__call(chunk, err)
    if chunk == "" then
	return true
    end
    if not chunk then
	return self:add(nil, err)
    end

    local acc, lastpos, state, datalen, dataleft, data = self.acc, self.lastpos, self.state, self.datalen, self.dataleft, self.data

    acc = acc .. chunk

    while lastpos < #acc or state == "EMIT" do
	local newpos
	if state == "DATA#" then
	    datalen, newpos = decode_uint(acc, lastpos + 1)
	    if datalen then
		lastpos = newpos
		state = (datalen == 0) and "EMIT" or "FIRSTDATA"
	    end
	elseif state == "FIRSTDATA" then
	    local avail = #acc - lastpos
	    if avail >= datalen then
		data = acc:sub(lastpos+1, lastpos+datalen)
		lastpos = lastpos + datalen
		state = "EMIT"
	    else
		data = acc:sub(lastpos+1)
		dataleft = datalen - #data
		data = { data }
		lastpos = #acc
		state = "CONTDATA"
	    end
	elseif state == "CONTDATA" then
	    local avail = #acc - lastpos
	    if avail >= dataleft then
		data[#data + 1] = acc:sub(lastpos+1, lastpos+dataleft)
		lastpos = lastpos + dataleft
		data = concat(data)
		state = "EMIT"
	    else
		local newdata = acc:sub(lastpos+1)
		dataleft = dataleft - #newdata
		data[#data + 1] = newdata
		lastpos = #acc
	    end
	elseif state == "EMIT" then
	    local success, err = self:add(data)
	    data = nil
	    if not success then
		return success, err
	    end
	    state = "DATA#"
	end
    end
    if lastpos == #acc then
	lastpos, acc = 0, ""
    end
    self.acc, self.lastpos, self.state, self.datalen, self.dataleft, self.data = acc, lastpos, state, datalen, dataleft, data
    return true
end

function M:add(chunk, err)
    if not self.max then
	self.max = 0
    end
    self.max = self.max + 1
    if err ~= nil then
	self.blocks[self.max] = { chunk, err }
    else
	self.blocks[self.max] = chunk
    end
    if self.notify then
	copas.wakeup(self.notify)
    end
    return true
end

function M:init_wait()
    local me = coroutine.running()
    if not me then
	return false, "No running coroutine"
    end
    return me
end

function M:recv(timeout)
    if timeout then
	local success, err = self:recv()
	if success == nil and err == nil then
	    self.notify = assert(self:init_wait())
	    copas.sleep(tonumber(timeout) or -1)
	    self.notify = nil
	else
	    if err ~= nil then
		return success, err
	    else
		return success
	    end
	end
    end
    if self.max then
	local min = self.min or 0
	min = min + 1
	local result = self.blocks[min]
	if min > self.max then
	    self.min, self.max, self.blocks = nil, nil, {}
	else
	    self.min = min
	end
	if type(result) == "table" then
	    return result[1], result[2]
	else
	    return result
	end
    end
end

function M:close()
    self.lowimpl(nil)
end

return construct
