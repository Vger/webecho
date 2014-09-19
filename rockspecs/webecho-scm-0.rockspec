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
    },
  },
}
