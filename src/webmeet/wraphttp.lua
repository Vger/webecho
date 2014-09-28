local wraptcp = require "webmeet.wraptcp"
local socket = require "socket"
local ltn12 = require "ltn12"
local http = require "socket.http"
local M = {}
local concat = table.concat or concat

function M.trequest(request)
    request.create = wraptcp
    return http.request(request)
end

function M.srequest(u, b)
    local t = {}
    local reqt = {
	url = u,
	sink = ltn12.sink.table(t)
    }
    if b then
	reqt.source = ltn12.source.string(b)
	reqt.headers = {
	    ["content-length"] = string.len(b),
	    ["content-type"] = "application/x-www-form-urlencoded"
	}
	reqt.method = "POST"
    end

    local code, headers, status = socket.skip(1, M.trequest(reqt))
    return concat(t), code, headers, status
end

M.request = socket.protect(function(reqt, body)
    if type(reqt) == "string" then
	return M.srequest(reqt, body)
    else
	return M.trequest(reqt)
    end
end)

return M
