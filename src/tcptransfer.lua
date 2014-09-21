-- Bind tcp socket to local address/port and transfer data to/from webecho server

local copas = require "copas"
local ltn12 = require "ltn12"
local http = require "socket.http"
local concat = table.concat or concat

local BLOCKSIZE = 2048
local last_channel = 0
local channels = {}

local CMD_OPEN = 1
local CMD_DATA = 2
local CMD_CLOSE = 3

local wrapped_connect
do
    local function handle_connect(self, ...)
	self.wrapped = copas.wrap(self.skt)
	return ...
    end

    function wrapped_connect(self, ...)
	return handle_connect(self, self.skt:connect(...))
    end
end

local wrapped_master = {}

wrapped_master.copasmeth = {}
wrapped_master.plainmeth = {}

local function create_method(src, key)
    if src == 'copasmeth' then
	return function(self, ...)
	    return self.wrapped[key](self.wrapped, ...)
	end
    elseif src == 'plainmeth' then
	return function(self, ...)
	    return self.skt[key](self.skt, ...)
	end
    end
end

function wrapped_master:__index(key)
    if key == 'connect' then
	return wrapped_connect
    end
    local value = self.wrapped[key]
    local src = 'copasmeth'
    if value == nil then
	value = self.skt[key]
	src = 'plainmeth'
    end
    if type(value) ~= 'function' then
	return value
    end
    local cachemeth = wrapped_master[src]
    local wrapmeth = cachemeth[key]
    if not wrapmeth then
	wrapmeth = create_method(src, key)
	cachemeth[key] = wrapmeth
    end
    return wrapmeth
end

-- Wrap TCP socket creation/connection so it works inside COPAS
local function wrapped_connect()
    local newskt, err = socket.tcp()
    if not newskt then
	return newskt, err
    end
    return setmetatable({ skt = newskt }, wrapped_master)
end

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

-- Create a source that sends the body of the POST request.
-- Returns the source function and a function to add new chunks to the source
local function create_post_source(post_request)
    local chunks = nil
    local me = nil
    local chunk_write = 0
    local chunk_read = 0

    local post_source

    me = create_request_thread(post_request)

    function post_source()
	-- No chunks added since last reset?
	if not chunks then
	    return nil
	end

	-- As long as we got chunks, report them
	if chunk_read < chunk_write then
	    chunks[chunk_read] = nil
	    chunk_read = chunk_read + 1
	    return chunks[chunk_read]
	end

	-- Reset
	chunks = nil
	chunk_write = 0
	chunk_read = 0

	-- Sleep for 60 seconds or until woken up
	copas.sleep(60)

	return post_source()
    end

    local function add_chunk(set_chunk)
	if not set_chunk or set_chunk == "" then
	    return
	end

	chunks = chunks or {}

	-- Add the chunk and wake up poster thread
	chunk_write = chunk_write + 1
	chunks[chunk_write] = set_chunk
	if coroutine.status(me) == "dead" then
	    -- Last HTTP request failed: start new HTTP request and
	    -- resend last chunk if there's any outstanding.
	    if chunk_read < chunk_write-1 then
		chunk_read = chunk_read - 1
	    end
	    me = copas.addthread(create_request_thread(post_request))
	end
	copas.wakeup(me)
    end

    return post_source, add_chunk
end

local function create_get_sink(get_request)
    local state = 1
    local acc = ""
    local lastpos = 0

    local cmd
    local channel_idx
    local data_len
    local data_left
    local data

    local function emit(cmd, channel_idx, data)
	-- TODO
    end

    return function(chunk, err)
	if not chunk or chunk == "" then
	    return true
	end
	acc = acc .. chunk

	while lastpos < #acc do
	    if state == 1 then
		lastpos = lastpos + 1
		cmd = string.byte(acc, lastpos)
		data = nil
		state = 2
	    elseif state == 2 then
		local newpos
		channel_idx, newpos = decode_uint(acc, lastpos + 1)
		if channel_idx then
		    lastpos = newpos
		    state = 3
		end
	    elseif state == 3 then
		local newpos
		data_len, newpos = decode_uint(acc, lastpos + 1)
		if data_len then
		    lastpos = newpos
		    if data_len == 0 then
			state = 7
		    else
			state = 4
		    end
		end
	    elseif state == 4 then
		local avail = #acc - lastpos
		if avail > data_len then  -- len = endpos - startpos + 1
		    data = acc:sub(lastpos+1, lastpos+data_len)
		    lastpos = lastpos + data_len
		    state = 7
		else
		    data = acc:sub(lastpos+1)
		    data_left = data_len - #data
		    data = { data }
		    lastpos = #acc
		    state = 5
		end
	    elseif state == 5 then
		local avail = #acc - lastpos
		if avail > data_left then
		    data[#data + 1] = acc:sub(lastpos+1, lastpos+data_left)
		    lastpos = lastpos + data_left
		    state = 6
		else
		    local newdata = acc:sub(lastpos+1)
		    data_left = data_left - #newdata
		    data[#data + 1] = new_data
		    lastpos = #acc
		end
	    elseif state == 6 then
		data = concat(data)
		state = 7
	    elseif state == 7 then
		emit(cmd, channel_idx, data)
		state = 1
	    end
	end
	if lastpos == #acc then
	    lastpos, acc = 0, ""
	end
	return true
    end
end

local encode_uint
function encode_uint(value)
    local lowvalue = value % 128
    local nextvalue = (value - lowvalue) / 128
    if nextvalue == 0 then
	return string.char(lowvalue)
    else
	return string.char(lowvalue + 128) .. encode_uint(nextvalue)
    end
end

local ENCODED_ZERO = encode_uint(0)

local decode_uint
function decode_uint(str, startpos)
    local value = string.byte(str, startpos)
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

local function send_command(cmd, channel_idx, data)
    local channel = channels[channel_idx]
    local send = channel.send
    local encode_idx = encode_uint(channel_idx)
    if data then
	send(cmd .. encode_idx .. encode_uint(#data) .. data)
    else
	send(cmd .. encode_idx .. ENCODED_ZERO)
    end
end

local function read_data(channel_idx, data)
    send_command(CMD_DATA, channel_idx, data)
end

local function setup_http_vars(pathsend, pathrecv, httphost, httpport, proxy, headers)
    pathsend = pathsend or ""
    pathrecv = pathrecv or ""
    if pathsend == pathrecv then
	error("URI path for send and receive can't be the same")
    end

    httpport = tonumber(httpport)
    if not httpport or httpport > 65535 or httpport < 1 then
	httpport = 80
    end
    if httphost == nil or httphost == "" then
	httppost = "127.0.0.1"
	httpport = 8888
    end

    local hostheader = httphost .. (httpport ~= 80 and (':' .. httpport) or '')
    local post_headers = {
	["Host"] = hostheader,
	["Content-Type"] = 'application/x-www-form-urlencoded',
    }
    local get_headers = {
	["Host"] = hostheader,
    }
    if type(headers) == "table" then
	for k,v in pairs(headers) do
	    post_headers[k] = v
	    get_headers[k] = v
	end
    end
    local post_request = {
	url = "http://" .. hostheader .. "/" .. pathsend,
	method = "POST",
	proxy = proxy,
	create = wrapped_connect,
	headers = post_headers,
    }
    local post_source, post_send = create_post_source(post_request)
    post_request.source = post_source
    local get_request = {
	url = "http://" .. hostheader .. "/" .. pathrecv,
	method = "GET",
	proxy = proxy,
	create = wrapped_connect,
    }
    local get_sink = create_get_sink(get_request)
    get_request.sink = get_sink
    return post_send, get_request
end

local function handler_end(channel_idx)
    local channel = channels[channel_idx]
    if not channel then
	return
    end
    local localskt = channel['local']
    if localskt then
	localskt:close()
    end
    channels[channel_idx] = nil
end

local function main_handler(server, skt, post_send, get_vars)
    local channel = {
	['local'] = skt,
	['get'] = get_vars,
	['send'] = post_send,
    }

    if server then
	-- new socket connected to server, open a channel
	last_channel = last_channel + 1
	local channel_idx = last_channel
	channels[channel_idx] = channel
	copas.setErrorHandler(function(msg, co, skt)
	    handler_end(channel_idx)
	    print(msg)
	end)
	assert(send_command(CMD_OPEN, channel_idx))
    else
	skt:settimeout(0)
	-- TODO: get index for channel
    end

    while channels[channel_idx] == channel do
	local data, err, partial = copas.receivePartial(skt, BLOCKSIZE)
	if not data then
	    if err == "timeout" then
		read_data(channel_idx, partial)
	    else
		if partial ~= "" and partial ~= nil then
		    read_data(channel_idx, partial)
		end
		error("Can't read from local endpoint: " .. tostring(err))
	    end
	end
    end
end

local function get_handler(server, post_send, get_vars)
    return function(skt)
	main_handler(server, skt, post_send, get_vars)
    end
end

local function setup(server, bindhost, bindport, pathsend, pathrecv, httphost, httpport, proxy, headers)
    local handler = get_handler(server, setup_http_vars(pathsend, pathrecv, httpaddr, httpport, proxy, headers))
    if server then
	local serverskt = socket.bind(bindhost, bindport)
	copas.addserver(server, handler)
    end
end

return setup
