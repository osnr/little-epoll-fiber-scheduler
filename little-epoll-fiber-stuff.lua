local ffi = require 'ffi'
ffi.cdef[[
int epoll_create1(int flags);
typedef union epoll_data {
    void    *ptr;
    int      fd;
    uint32_t u32;
    uint64_t u64;
} epoll_data_t;
struct epoll_event {
    uint32_t     events;    /* Epoll events */
    epoll_data_t data;      /* User data variable */
};
int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event);
int epoll_wait(int epfd, struct epoll_event *events,
               int maxevents, int timeout);
]]

local function cassert(cond)
   if not cond then error(ffi.string(ffi.C.strerror(ffi.errno()))) end
end
coroutine.id = function(co) return tonumber(tostring(co):sub(8)) end

local fiber = {
   _fibers={},
   _fibers_to_resume={}
}
fiber.dispatch = function(f)
   local co = coroutine.create(f)
   fiber._fibers[coroutine.id(co)] = co
   table.insert(fiber._fibers_to_resume, co)
end
fiber.await = function(fd)
   local co = coroutine.running()

   -- rearm
   local ev = ffi.new('struct epoll_event')
   ev.data.u32 = coroutine.id(co)
   ffi.C.epoll_ctl(fiber._epfd, ffi.C.EPOLL_CTL_ADD, fd, ev)

   -- TODO: yield
end
fiber.sleep = function(us)
   -- FIXME: it's just await on a timerfd
   coroutine.yield()
end

fiber.runloop = function()
   fiber._epfd = ffi.C.epoll_create1(0)
   cassert(fiber._epfd ~= -1)
   while true do
      local numevents = ffi.C.epoll_wait(fiber._epfd, events, 1024, 50)
      for i = 0, numevents - 1 do
         local ev = events[i]
         table.insert(fiber._fibers_to_resume, fiber._fibers[ev.data.u32])
      end
      
      for _, co in ipairs(fiber._fibers_to_resume) do
         coroutine.resume(co)
      end
      fiber._fibers_to_resume = {}
   end
end

-- Usage:

fiber.dispatch(function()
      print('hello')
      fiber.sleep(500000)
      print('bye!')
end)

fiber.runloop()
