-- Create a sink that parses data from remote and invokes callback to
-- user-supplied function "emit_callback", which will receive two
-- parameters: Request Index, Data

local concat = table.concat or concat
local byte = string.byte
local decode_uint, construct

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

function construct(emit_callback)
    if not emit_callback then
	return nil, "No callback supplied to webmeet.incoming"
    end

    local state = "REQUESTID"
    local acc = ""
    local lastpos = 0

    local reqid
    local datalen
    local dataleft
    local data

    return function(chunk, err)
	if chunk == "" then
	    return true
	end
	if not chunk then
	    return emit_callback(nil, err)
	end

	acc = acc .. chunk

	while lastpos < #acc or state == "EMIT" do
	    local newpos
	    if state == "REQUESTID" then
		reqid, newpos = decode_uint(acc, lastpos + 1)
		if reqid then
		    lastpos = newpos
		    state = "DATA#"
		end
	    elseif state == "DATA#" then
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
		local success, err = emit_callback(reqid, data)
		data = nil
		if not success then
		    return success, err
		end
		state = "REQUESTID"
	    end
	end
	if lastpos == #acc then
	    lastpos, acc = 0, ""
	end
	return true
    end
end

return construct
