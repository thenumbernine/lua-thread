require 'ext.gc'
local ffi = require 'ffi'
local class = require 'ext.class'
local pthread = require 'ffi.req' 'c.pthread'	-- pthread_mutex_t
local thread_assert = require 'thread.assert'


local pthread_cond_t_1 = ffi.typeof'pthread_cond_t[1]'
local pthread_cond_t_ptr = ffi.typeof'pthread_cond_t*'


local Cond = class()

function Cond:init()
	self.id = pthread_cond_t_1()
	thread_assert(pthread.pthread_cond_init(self.id, nil), 'pthread_cond_init')
end

function Cond:destroy()
	if not self.id then return true end
	local err = pthread.pthread_mutex_destroy(self.id)
	if err == 0 then self.id = nil end
	return 0 == err, err
end

function Cond:__gc()
	self:destroy()
end

-- wrap a previously created pthread_cond_t* and overwrite the destroy function
-- static method
function Cond:wrap(id)
	return setmetatable({
		id = ffi.cast(pthread_cond_t_ptr, id),
		__gc = function() end,
	}, Cond)
end

function Cond:signal()
	local err = pthread.pthread_cond_signal(self.id)
	return 0 == err, err
end

function Cond:broadcast()
	local err = pthread.pthread_cond_broadcast(self.id)
	return 0 == err, err
end

function Cond:wait(mutex)
	local err = pthread.pthread_cond_wait(self.id, mutex.id)
	return 0 == err, err
end

function Cond:timedwait(mutex, abstime)
	local err = pthread.pthread_cond_timedwait(self.id, mutex.id, abstime)
	return 0 == err, err
end

return Cond
