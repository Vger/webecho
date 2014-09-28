-- Receive data from remote

local copas = require "copas"
local http = require "webmeet.wraphttp"
local construct

-- Returns a function for setting the sink of this HTTP getter.
function construct(get_request)
    if type(get_request) == "string" then
	local u = get_request
	get_request = {
	    url = u,
	    method = "GET",
	    headers = {
		["Connection"] = "keep-alive",
		["TE"] = "chunked",
	    },
	}
    end

    local sink = nil
    get_request.sink = function(chunk, src_err)
	if not sink then
	    return nil
	end
	return sink(chunk, src_err)
    end

    return function(set_sink)
	sink = set_sink
	
	if set_sink then
	    copas.addthread(function()
		while sink == set_sink do
		    http.request(get_request)
		end
	    end)
	end
    end
end

return construct
