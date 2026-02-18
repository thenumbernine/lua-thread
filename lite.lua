-- This is everything that goes into thread/thread.lua except the pthread stuff
-- It's useful for encasing Lua environments in other platforms' threads, i.e. in Java
require 'ext.gc'	-- enable __gc for Lua tables in LuaJIT
local ffi = require 'ffi'
local class = require 'ext.class'


local threadFuncTypeName = 'void*(*)(void*)'
local threadFuncType = ffi.typeof(threadFuncTypeName)


local LiteThread = class()

if langfix then
	LiteThread.Lua = require 'lua.langfix'
else
	LiteThread.Lua = require 'lua'
end

--[[
args:
	code = Lua code to load and run on the new thread
	arg = cdata to pass to the thread
	init = callback function to run on the thread to initialize the new Lua state before starting the thread
-or-
args = code of the thread
--]]
function LiteThread:init(args)
	if type(args) == 'string' then args = {code = args} end

	local code = args.code
	local arg = args.arg

	-- each thread needs its own lua_State
	self.lua = self.Lua()

	-- load our thread code within the new Lua state
	-- this will put a function on top of self.lua's stack
	--self.lua:load(code)

	-- or lazy way for now, just gen the code inside here:
	-- TODO instead of the extra lua closure, how about using self.lua:load() to load the code as a function, then use the lua lib for calling ffi.cast?
	-- then call it with xpcall?
	-- but no, the xpcall needs to be called from the new thread,
	-- so maybe it is safest to do here?
	local funcptr = self.lua([[
function _G.run(arg)
	local function collect(exitStatus, ...)
		_G.exitStatus = exitStatus
		if not exitStatus then
			_G.errmsg = ...
		else
			_G.results = table.pack(...)
		end
	end

	-- assign a global of the results when it's done
	collect(xpcall(function()
]]..code..[[
	end, function(err)
		return err..'\n'..debug.traceback()
	end))

	return nil	-- so it can be cast to void* safely, for the thread's cfunc closure's sake
end

-- just in case luajit gc's this, assign it to _G
-- in its docs luajit warns that you have to gc the closures manually, so I think I'm safe (except for leaking memory)
local ffi = require 'ffi'
_G.funcptr = ffi.cast(']]..threadFuncTypeName..[[', _G.run)
return _G.funcptr
]])

	if args.init then
		args.init(self)
	end

	self.funcptr = ffi.cast(threadFuncType, funcptr)

	self.arg = arg	-- store before cast, so nils stay nils, for ease of truth testing
	local argtype = type(arg)
	if not (argtype == 'nil' or argtype == 'cdata') then
		error("I don't know how to pass arg of type "..argtype.." into a new thread")
	end
end

function LiteThread:__gc()
	self:close()
end

function LiteThread:close()
	if self.lua then
		self.lua:close()
		self.lua = nil
	end
end

function LiteThread:showErr(msg)
	local WG = self.lua.global
	if not WG.exitStatus then
		io.stderr:write((msg and msg..' ' or 'thread '..tostring(self))..'error '..tostring(WG.errmsg)..'\n')
	end
end

return LiteThread 
