webecho
=======

Simple webserver that echoes back posted data. Each unique path portion of the URI acts as a mailbox where HTTP POST requests can be seen by HTTP GET requests.

Sample usage
------------
Start the webserver with:
	$ path/to/deploy/directory/bin/westandalone.lua

Open two new terminal windows and execute in each window (GET request):
	$ curl http://127.0.0.1:8888/myecho/

Open a new terminal window and execute (POST requests):
	$ curl --data-binary "testing echo" http://192.168.56.15:8888/myecho/
	$ curl --data-binary "more data" http://192.168.56.15:8888/myecho/

As long as curl stays connected, both terminal windows that executed the GET request should see the posted data.

Installation
============

Latest Git Revision
-------------------

With LuaRocks 2.1.2:

	$ luarocks install https://raw.githubusercontent.com/Vger/webecho/master/rockspecs/webecho-scm-0.rockspec
