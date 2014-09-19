#!/usr/bin/env lua52

local httpd = require "xavante.httpd"
local copas = require "copas"
local format = string.format

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
    end

    function remove_receiver(path, receiver)
	local pathinfo = pathmap[path]
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
    if req.cmd_version ~= 'HTTP/1.1' then
	http_error(req, res, '505 HTTP Version Not Supported', 'Needs chunked transfer')
    else
	local body = ''
	res.chunked = true
	res.headers['Content-type'] = 'text/plain; charset=ISO-8859-1'
	res.headers['Cache-Control'] = 'no-cache'
	res.headers['Expires'] = '0'
	res.headers['Transfer-Encoding'] = 'chunked'
	add_receiver(req.relpath, req)
	req.me = coroutine.running()
	repeat
	    res:send_data(body)
	    req.waked = nil
	    copas.sleep(60)
	    body = req.waked
	until not body
    end
end

local function handle_post_chunk(req, res, length)
    if not length or length == 0 then
	return
    end
    local body = req.socket:receive(length)
    local msg
    for receiver_req in receivers_iterator(req.relpath) do
	local co = receiver_req.me
	if co then
	    msg = msg or format('%x\r\n%s\r\n', #body, body)
	    receiver_req.waked = msg
	    copas.wakeup(receiver_req.me)
	end
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
	if length and length ~= 0 then
	    handle_post_chunk(req, res, length)
	end
    end
end

local function mainhandler(req, res)
    if req.cmd_mth == "GET" then
	local function cleanup_get(msg, co, skt)
	    -- Remove connection from active list
	    remove_receiver(req.relpath, req)
	    req.me = nil
	    if co then
		httpd.errorhandler(msg, co, skt)
	    end
	    copas.setErrorHandler(httpd.errorhandler)
	end
	copas.setErrorHandler(cleanup)
	handle_get(req, res)
	cleanup_get()
    elseif req.cmd_mth == "POST" then
	handle_post(req, res)
    else
	res.headers['Allow'] = 'GET, POST'
	httpd.err_405(req, res)
    end
end

return mainhandler
