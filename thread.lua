-- posix threads library
require 'ext.gc'	-- enable __gc for Lua tables in LuaJIT
local ffi = require 'ffi'
local pthread = require 'ffi.req' 'c.pthread'
local unistd = require 'ffi.req' 'c.unistd'	-- sysconf
local LiteThread = require 'thread.lite'
local thread_assert = require 'thread.assert'

local voidp = ffi.typeof'void*'
local voidp_1 = ffi.typeof'void*[1]'
local pthread_t = ffi.typeof'pthread_t'
local pthread_t_1 = ffi.typeof'pthread_t[1]'


local Thread = LiteThread:subclass()

--[[
args:
	code = code, handled by super
	arg = cdata to pass to the thread
	init = callback function to run on the thread to initialize the new Lua state before starting the thread
--]]
function Thread:init(args)
	Thread.super.init(self, args)

	if type(args) == 'string' then args = {code = args} end
	local arg = args.arg

	if args.init then
		args.init(self)
	end

	self.arg = arg	-- store before cast, so nils stay nils, for ease of truth testing
	local argtype = type(arg)
	if not (argtype == 'nil' or argtype == 'cdata') then
		error("I don't know how to pass arg of type "..argtype.." into a new thread")
	end

	local id = pthread_t_1()
	thread_assert(pthread.pthread_create(
		id,
		nil,
		self.funcptr,
		ffi.cast(voidp, self.arg)
	), 'pthread_create')
	self.id = pthread_t(id[0])
end

-- wrap a previously created thread handle
-- static function
function Thread:wrap(id)
	return setmetatable({
		id = pthread_t(self.id),
		close = function() end,
	}, Thread)
end

function Thread:join()
	local result = voidp_1()
	thread_assert(pthread.pthread_join(self.id, result), 'pthread_join')
	return result[0]
end

-- should be called from the thread
function Thread:exit(value)
	pthread.pthread_exit(ffi.cast(voidp, value))
end

function Thread:detach()
	thread_assert(pthread.pthread_detach(self.id))
end

-- returns a pthread_t, not a Thread
-- I could wrap this in a Thread, but it'd still have no Lua state...
function Thread:self()
	return pthread.pthread_self()
end

function Thread.__eq(a,b)
	--[[ this seems like a nice thing for flexibility of testing Thread or pthread_t
	-- but then again LuaJIT goes and made its __index fail INTO AN ERROR INSTEAD OF JUST RETURNING NIL
	-- which I can circumvent using op.safeindex/xpcall
	-- but that'd slow things down a lot
	-- so instead this is only going to work for Thread objects
	a = a.id or a
	b = b.id or b
	--]]
	return 0 ~= pthread.pthread_equal(a.id, b.id)
end

-- TODO pthread_attr_* functions
-- TODO pthread_*sched* functions
-- TODO pthread_*cancel* functions
-- TODO pthread_*key* functions
-- TODO a lot more

function Thread.numThreads()
	return tonumber(unistd.sysconf(unistd._SC_NPROCESSORS_ONLN))
end

return Thread
