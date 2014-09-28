#!/usr/bin/env lua52

local httpd = require 'xavante.httpd'
local copas = require 'copas'
local format = string.format
local concat = table.concat or concat

local add_receiver
local remove_receiver
local receivers_iterator
do
    local pathmap = {}

    function add_receiver(path, receiver)
	local pathinfo = pathmap[path]
	if not pathinfo then
	    pathmap[path] = {}
	    pathinfo = pathmap[path]
	end
	pathinfo[receiver] = true
	receiver.path = path
    end

    function remove_receiver(receiver)
	local path = receiver.path
	local pathinfo = path and pathmap[path]
	if not pathinfo then
	    return
	end
	pathinfo[receiver] = nil
	if not next(pathinfo) then
	    pathmap[path] = nil
	end
    end

    local function dummy_iter()
	return nil
    end

    function receivers_iterator(path)
	local pathinfo = pathmap[path]
	if pathinfo then
	    return next, pathinfo
	else
	    return dummy_iter
	end
    end
end

local function http_error(req, res, status, extrainfo)
    res.content = format([[
<html>
<head><title>%s</title></head>
<body bgcolor="white">
<center><h1>%s</h1></center>
<hr><center>%s</center>
</body>
<html>
	]], status, status, extrainfo or req.serversoftware)
    res:add_header('status', status)
    res.headers['Content-Type'] = 'text/html'
end

local function handle_get(req, res)
    local version = req.cmd_version
    local remember_chunked = nil
    if not version then
	-- Looks somewhat like a HTTP/0.9 connection, don't send any headers.
	res.sent_headers = true
    else
	if version ~= 'HTTP/1.1' and version ~= 'HTTP/1.0' then
	    return http_error(req, res, '505 HTTP Version Not Supported', version .. ' is not supported')
	end
	res.headers['Content-type'] = 'text/plain; charset=ISO-8859-1'
	res.headers['Expires'] = '0'
	res.headers['Accept-Ranges'] = 'none'
	if version == 'HTTP/1.0' then
	    res.headers['Connection'] = 'close'
	else
	    res.headers['Cache-Control'] = 'no-cache'
	    res.headers['Transfer-Encoding'] = 'chunked'
	    res.headers['Connection'] = 'Keep-Alive'
	    remember_chunked = true
	end
    end
    res:send_headers()

    -- Fool httpd.send_response to keep connection open
    local remember_contentlength = res.headers['Content-Length']
    res.headers['Content-Length'] = 0
    req.headers['connection'] = 'Keep-Alive'

    add_receiver(req.relpath, res)
    req.res = res

    res.me = copas.addthread(function()
	local function cleanup()
	    remove_receiver(res)
	    res.me = nil
	    req.res = nil
	    if res.notify then
		copas.wakeup(res.notify)
		res.notify = nil
	    end
	end
	copas.setErrorHandler(cleanup)

	copas.sleep(-1)
	res.chunked = remember_chunked
	res.headers['Content-Length'] = remember_contentlength

	local body
	while true do
	    body = res.waked
	    if not body then
		break
	    end
	    if type(body) == 'table' then
		body = concat(body)
		res.waked = body
	    end

	    -- Before send_data, body == res.waked
	    res:send_data(body)

	    -- Between send_data and the next comparison,
	    -- another thread might have altered res.waked
	    if body == res.waked then
		-- No more data to send for now.
		res.waked = nil

		-- Notify thread that we're done with current data
		if res.notify then
		    copas.wakeup(res.notify)
		    res.notify = nil
		end

		copas.sleep(-1)
	    end
	end
	cleanup()
    end)
end

local function send_to_receiver(res, body, block)
    if res.me then
	if res.waked == nil then
	    res.waked = body
	    copas.wakeup(res.me)
	else
	    -- Already sending some other data
	    if body == nil then
		-- Caller signals that we should end as soon as possible
		res.waked = nil
		res.me = nil
	    else
		-- Accumulate data to send
		if type(res.waked) == "string" then
		    res.waked = {}
		end
		res.waked[#res.waked + 1] = body
	    end
	end
	if block then
	    -- Block this thread until the other thread has finished sending
	    res.notify = coroutine.running()
	    copas.sleep(-1)
	end
    end
end

local function handle_post_chunk(req, res, length)
    if not length or length <= 0 then
	return
    end
    local body = req.socket:receive(length)
    for receiver_res in receivers_iterator(req.relpath) do
	send_to_receiver(receiver_res, body)
    end
end

local function handle_post(req, res)
    if req.headers['expect'] == '100-continue' then
	res.socket:send('HTTP/1.1 100 Continue\r\n\r\n')
    end
    local te = req.headers['transfer-encoding']
    if te and te ~= 'identity' then
	while true do
	    -- Assume chunked
	    local line = req.socket:receive()
	    if not line then
		http_error(req, res, '400 Bad Request', 'No size of chunk specified')
		return
	    end
	    local size = tonumber(line:gsub(';.*', ''), 16)
	    if not size then
		http_error(req, res, '400 Bad Request', 'Size specified is not hexadecimal')
		return
	    end
	    if size > 0 then
		-- this is not the last chunk, get it and skip CRLF
		handle_post_chunk(req, res, size)
		req.socket:receive()
	    else
		-- last chunk, read trailers
		httpd.read_headers(req)
		break
	    end
	end
    else
	local length = req.headers['content-length']
	if length then
	    handle_post_chunk(req, res, tonumber(length))
	end
    end
    res.statusline = 'HTTP/1.1 204 No Content'
    res.headers['Content-Length'] = 0
    res:send_headers()

    -- Fool httpd.send_response to keep connection open for HTTP/1.1 requests
    if req.cmd_version == 'HTTP/1.1' then
	req.headers['connection'] = 'Keep-Alive'
    end
end

local function mainhandler(req, res)
    local oldresponse = req.res
    if oldresponse then
	-- Finish old request/response cycle.
	send_to_receiver(oldresponse, nil, true)
	assert(req.res == nil)
	if oldresponse.chunked then
	    oldresponse.socket:send('0\r\n\r\n')
	end
    end
    if req.cmd_mth == 'GET' then
	handle_get(req, res)
    elseif req.cmd_mth == 'POST' then
	handle_post(req, res)
    else
	res.headers['Allow'] = 'GET, POST'
	httpd.err_405(req, res)
    end
end

return mainhandler
