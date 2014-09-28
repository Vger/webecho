package = "webecho"
version = "scm-0"
source = {
   url = "git://github.com/Vger/webecho.git",
}
description = {
   summary = "Long-polling xavante handler that for each URI path echoes back POST data to browsers who GET.",
   homepage = "https://github.com/Vger/webecho",
   license = "MIT/X11",
}
dependencies = {
   "lua >= 5.1",
   "xavante",
}

build = {
  type = "none",
  install = {
    bin = {
      ["westandalone.lua"] = "src/westandalone.lua",
    },
    lua = {
      ["webecho"] = "src/webecho.lua",
      ["webmeet.incoming"] = "src/webmeet/incoming.lua",
      ["webmeet.outgoing"] = "src/webmeet/outgoing.lua",
      ["webmeet.wraptcp"] = "src/webmeet/wraptcp.lua",
      ["webmeet.wraphttp"] = "src/webmeet/wraphttp.lua",
      ["webmeet.queue"] = "src/webmeet/queue.lua",
      ["webmeet.poster"] = "src/webmeet/poster.lua",
      ["webmeet.getter"] = "src/webmeet/getter.lua",
      ["webmeet.requester"] = "src/webmeet/requester.lua",
      ["webmeet.responder"] = "src/webmeet/responder.lua",
    },
  },
}
