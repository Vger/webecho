-- Send data to remote (which is parsed by incoming.lua)

local meta = {}
local char = string.char
local encode_uint, construct

function encode_uint(value)
    local lowvalue = value % 128
    local nextvalue = (value - lowvalue) / 128
    if nextvalue == 0 then
	return char(lowvalue)
    else
	return char(lowvalue + 128) .. encode_uint(nextvalue)
    end
end

function meta:__call(request_id, data)
    local datalen = type(data) == "string" and #data or 0
    local encoded = encode_uint(tonumber(request_id)) .. encode_uint(datalen) .. (datalen ~= 0 and data or "")
    self.lowimpl(encoded)
end

function construct(sendimpl)
    local self = setmetatable({ lowimpl = sendimpl }, meta)
    return self
end

return construct
