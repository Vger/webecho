local xavante = require "xavante"
local webecho = require "webecho"

local host = "*"
local port = 8888

local simplerules = {
    {
	match = ".",
	with = webecho,
    },
}

local conf = {
    server = { host = host, port = port },

    defaultHost = {
	rules = simplerules
    },
}

xavante.HTTP(conf)
xavante.start()
