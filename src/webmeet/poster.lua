local copas = require "copas"
local http = require "webmeet.wraphttp"

local function create_request_thread(req)
    return coroutine.create(function()
	while not req.done do
	    copas.sleep(-1)
	    local success, code, headers = http.request(req)
	    if not success then
		return
	    end
	end
    end)
end

local function adapt_request(post_request)
    if type(post_request) == "string" then
	local u = post_request
	post_request = {
	    url = u,
	    method = "POST",
	    headers = {
		["Connection"] = "keep-alive",
		["Transfer-Encoding"] = "chunked",
	    }
	}
    end
    return post_request
end

-- Create a source that sends http POST request.
-- Return function to add new chunks to the POST body.
local function construct(post_request)
    local chunk = nil
    local me = nil
    local notify = nil

    post_request = adapt_request(post_request)
    post_request.source = function()
	-- No active chunk?
	if not chunk then
	    if notify then
		copas.wakeup(notify)
		notify = nil
	    end
	    copas.sleep(60)
	end
	local result = chunk
	if result == nil and notify then
	    copas.wakeup(notify)
	    notify = nil
	    post_request.done = true
	end
	chunk = nil
	return result
    end

    return function(set_chunk)
	if set_chunk == "" then
	    return
	end

	-- Wake up poster thread
	chunk = set_chunk
	if me == nil or coroutine.status(me) == "dead" then
	    -- Not connected to HTTP server, reconnect.
	    me = copas.addthread(create_request_thread(post_request))
	end
	copas.wakeup(me)
	notify = coroutine.running()
	if notify then
	    copas.sleep(-1)
	end
	return true
    end
end

return construct
