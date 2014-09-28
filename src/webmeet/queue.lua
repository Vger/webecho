-- Queue for incoming requests or replies.

local M = {}
local setmetatable = setmetatable
local handler
local construct

M.__index = M

function M:__call(reqid, data)
    if reqid == nil then
	if data then
	    self.err = data
	end
    else
	if (not self.min) or (reqid < self.min) then
	    self.min = reqid
	end
	if (not self.max) or (reqid > self.max) then
	    self.max = reqid
	end
	self.queue[reqid] = data
    end
    local notify = rawget(self, "notify")
    if notify then
	notify()
    end
    return true
end

-- Remove next request / reply from queue and return its value and identification
function M:get()
    local min, max, queue = self.min
    if not min then
	local err = self.err
	if err then
	    self.err = nil
	    return nil, err
	end
	return
    end
    local max, queue = self.max, self.queue
    for i = min,max do
	local value = queue[i]
	if value then
	    queue[i] = nil
	    self.min = i+1
	    return value, i
	end
    end
    self.min, self.max = nil, nil
end

function M:set_notify(notify)
    self.notify = notify
end

function construct()
    return setmetatable({
	queue = {},
	min = nil,
	max = nil,
    }, M)
end

return construct
