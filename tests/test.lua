#!/usr/bin/env luajit
local Thread = require 'thread'

-- it takes a few prints for them to conflict ... hundreds ... thousands ...
local th = Thread[[
for i=1,100 do
	print('hi within lua_State', _G, 'thread')
end
]]
for i=1,100 do
	print('hi from calling lua_State', _G)
end

th:join()
