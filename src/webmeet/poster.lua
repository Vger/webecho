local copas = require "copas"
local http = require "webmeet.wraphttp"

local function create_request_thread(req)
    return coroutine.create(function()
	while true do
	    copas.sleep(-1)
	    local success, code, headers = http.request(req)
	    if not success then
		return
	    end
	end
    end)
end

-- Create a source that sends http POST request.
-- Return function to add new chunks to the POST body.
local function construct(post_request)
    local chunk = nil
    local me = nil

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

    post_request.source = function()
	-- No active chunk?
	if not chunk then
	    copas.sleep(60)
	end
	local result = chunk
	chunk = nil
	return result
    end

    return function(set_chunk)
	if not set_chunk or set_chunk == "" then
	    return
	end

	-- Wake up poster thread
	chunk = set_chunk
	if me == nil or coroutine.status(me) == "dead" then
	    -- Not connected to HTTP server, reconnect.
	    me = copas.addthread(create_request_thread(post_request))
	end
	copas.wakeup(me)
    end
end

return construct
