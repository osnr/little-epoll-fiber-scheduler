# little-epoll-fiber-scheduler

Little epoll-based fiber scheduler. No dependencies besides LuaJIT.

Related to / a spin-off of <https://github.com/osnr/little-web-server>.

MIT license.

Only tested on Linux on a Raspberry Pi 4.

I don't know what I'm doing, so take this code with a grain of
salt. You can make concurrent fibers (coroutines, green threads,
whatever) that can block until a file descriptor is readable. The only
type of file descriptor I actually tested is timerfd, so all they do
in the example is sleep for periods of time, but it's supposed to
generalize to sockets and stuff.

```
$ luajit little-epoll-fiber-scheduler.lua
0.00	A: hello
1.00	A: it's been 1 second
2.00		[B: hi! 2s in]
5.00		[B: hi again! 2s + 3s in]
6.00	A: it's been another 5 seconds
```

(the two fibers A and B run concurrently & interleave!)
