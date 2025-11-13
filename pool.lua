local ffi = require 'ffi'
local template = require 'template'
local class = require 'ext.class'
local assert = require 'ext.assert'
local Thread = require 'thread'
local Semaphore = require 'thread.semaphore'
local numThreads = Thread.numThreads()


-- save code separately so the threads can cdef this too
-- TODO change design to be like Parallel: http://github.com/thenumbernine/Parallel
-- with critsec-mutex to access job pool, another mutex to notify when done
-- and only one semaphore-per-thread to notify to wakeup
local threadArgTypeCode = [[
typedef struct ThreadArg {
	sem_t *semReady;
	sem_t *semDone;
	volatile bool done;
} ThreadArg;
]]
ffi.cdef(threadArgTypeCode)


-- TODO should semaphore be created here?
-- TODO how to override ThreadArg?
local Worker = class()


local Pool = class()

Pool.Worker = Worker

local function getcode(self, code, i)
	local codetype = type(code)
	if codetype == 'string' then
	elseif codetype == 'table' then
		code = code[i]
	elseif codetype == 'function' then
		code = code(self, i-1)
	else
		error("can't interpret code of type "..codetype)
	end
	assert.type(code, 'string')
	return code
end

--[[
args:
	size = pool size, defaults to Thread.numThreads()
	initcode / code = string to provide worker code
		= table to provide worker code per index (1-based)
		= function(pool, index) to provide worker code per worker (0-based)
			where i is the 0-based index
--]]
function Pool:init(args)
	self.size = self.size or Thread.numThreads()
	for i=1,self.size do
		local worker = Worker()
		worker.semReady = Semaphore()
		worker.semDone = Semaphore()

		-- TODO how to allow the caller to override this
		local threadArg = ffi.new'ThreadArg'
		worker.arg = threadArg
		threadArg.done = false
		threadArg.semReady = worker.semReady.id
		threadArg.semDone = worker.semDone.id

		local initcode = getcode(self, args.initcode, i)
		local code = getcode(self, args.code, i)


		-- TODO in lua-lua, change the pcalls to use error handlers, AND REPORT THE ERRORS
		-- TODO how to separate init code vs update code and make it modular ...
		worker.thread = Thread(template([===[
local ffi = require 'ffi'
local assert = require 'ext.assert'
local Semaphore = require 'thread.semaphore'

-- will ffi.C carry across? 
-- because its the same luajit process?
-- nope, ffi.C is unique per lua-state
ffi.cdef[[<?=threadArgTypeCode?>]]

-- holds semaphores etc of the thread
assert(arg, 'expected thread argument')
assert.type(arg, 'cdata')
arg = ffi.cast('ThreadArg*', arg)

-- convert our sem_t* to our Semaphore.id.  (By default its sem_t[1], but sem_t* is interchangeable.)
-- looks like sem_destroy() can be called multiple times harmlessly, but if it ever crashes on any OS implementation, feel free to insert destroy=function() end to avoid multiple destroy calls.
local semReady = setmetatable({id=arg.semReady}, Semaphore)
local semDone = setmetatable({id=arg.semDone}, Semaphore)

<?=initcode or ''?>

semReady:wait()
while not arg.done do

	<?=code or ''?>

	semDone:post()
	semReady:wait()
end
]===],			{
					threadArgTypeCode = threadArgTypeCode,
					initcode = initcode,
					code = code,
				}),
			threadArg)

		self[i] = worker
	end
end

function Pool:ready()
	for _,worker in ipairs(self) do
		worker.semReady:post()
	end
end

function Pool:wait()
	for _,worker in ipairs(self) do
		worker.semDone:wait()
	end
end

function Pool:cycle()
	self:ready()
	self:wait()
end

-- pool's closed
function Pool:closed()
	for _,worker in ipairs(self) do
		local arg = worker.arg
		-- set thread done flag
		arg.done = true
		-- wake it up so it can break and return
		worker.semReady:post()
		-- join <-> wait for it to return
		worker.thread:join()
		-- destroy semaphores
		worker.semReady:destroy()
		worker.semDone:destroy()
		-- destroy thread Lua state:
		worker.thread:close()
	end
end

return Pool
