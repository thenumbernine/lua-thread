#!/usr/bin/env luajit
-- what do threads do while idle?
local ffi = require 'ffi'
local unistd = require 'ffi.req' 'c.unistd'	-- sleep

local pool = require 'thread.pool'{code=''}
pool:cycle()

-- this is up to you.  watch your CPU % and see what happens while the pool waits.
unistd.sleep(3)

pool:cycle()

pool:closed()
