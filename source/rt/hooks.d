module rt.hooks;

version(PSVita) version = RuntimeHooks;
version(CustomRuntimeTest) version = RuntimeHooks;
version(NintendoSwitch) version = RuntimeHooks;

version(WebAssembly)
{
    public import core.arsd.memory_allocation;
    void abort() pure nothrow @nogc
    {
        static import arsd.webassembly;
        arsd.webassembly.abort();
    }
}
else version(RuntimeHooks)
{
    ///Max is 64 megabytes
    enum MaxSize = 67_108_863;

    nothrow @nogc @trusted
    {
        version(PSVita)
        {
            extern(C) pure
            {
                pragma(mangle, "psv_abort")  void hookAbort();
                pragma(mangle, "psv_free")  void hookFree(ubyte* ptr);
                pragma(mangle, "sceClibPrintf")  int hookPrintf(const(char*) fmt, ...);
                pragma(mangle,  "psv_realloc")  ubyte* hookRealloc(ubyte* ptr, size_t newSize);
                pragma(mangle,  "psv_malloc")  ubyte* hookMalloc(size_t sz);
                pragma(mangle,  "psv_calloc")  ubyte* hookCalloc(size_t count, size_t newSize);
                pragma(mangle, "psv_isOnHeap")  int hookIsOnHeap(void* ptr);
                pragma(mangle, "psv_get_allocated_memory")  size_t hookGetAllocatedMemory();
            }
        }
        else
        {
            extern(C) @nogc nothrow
            {
                pure void exit(int exitCode);
                pure void hookAbort()
                {
                    // asm pure @nogc nothrow {int 3;}
                    exit(-1);
                }
                pure pragma(mangle, "free") void hookFree(ubyte* ptr);
                pure pragma(mangle, "realloc") ubyte* hookRealloc(ubyte* ptr, size_t newSize);
                pure pragma(mangle, "malloc") ubyte* hookMalloc(size_t sz);
                pure pragma(mangle, "calloc") ubyte* hookCalloc(size_t count, size_t newSize);
                pure pragma(mangle, "printf") int hookPrintf(const(char*) fmt, ...);
                version(NintendoSwitch)
                {
                    extern __gshared char __end__;
                    extern void* sbrk(ptrdiff_t incr);
                    bool hookIsOnHeap_(void* ptr)
                    {
                        size_t p = cast(size_t)ptr;

                        size_t heapStart = cast(size_t)&__end__;
                        size_t heapEnd = cast(size_t)sbrk(0);

                        return p>= heapStart && p < heapEnd;
                    }
                    pure bool hookIsOnHeap(void* ptr)
                    {
                        alias pureIsOnHeap = pure @nogc nothrow bool function(void*);
                        return (cast(pureIsOnHeap)&hookIsOnHeap_)(ptr);
                    }

                    struct mallinfo_t
                    {
                        size_t arena;    /* total space allocated from system */
                        size_t ordblks;  /* number of non-inuse chunks */
                        size_t smblks;   /* unused -- always zero */
                        size_t hblks;    /* number of mmapped regions */
                        size_t hblkhd;   /* total space in mmapped regions */
                        size_t usmblks;  /* unused -- always zero */
                        size_t fsmblks;  /* unused -- always zero */
                        size_t uordblks; /* total allocated space */
                        size_t fordblks; /* total non-inuse space */
                        size_t keepcost; /* top-most, releasable (via malloc_trim) space */
                    }
                    pure mallinfo_t mallinfo();

                    pure size_t hookGetAllocatedMemory()
                    {
                        return mallinfo().uordblks;
                    }

                }
            }
        }
        pure
        {

            size_t getMemoryAllocated()
            {
                return hookGetAllocatedMemory();
            }

            void abort(){hookAbort();}
            void free(ubyte* ptr, string file, size_t line) @nogc
            {
                hookFree(ptr);
            }

            ubyte[] malloc(size_t sz, string file = __FILE__, size_t line = __LINE__) 
            {
                return hookMalloc(sz)[0..sz];
            }
            ubyte[] realloc(ubyte* ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__)
            {
                return hookRealloc(ptr, newSize)[0..newSize];
            }

            ubyte[] realloc(ubyte[] ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__)
            {
                return realloc(ptr.ptr, newSize, file, line);
            }


            pragma(inline, true)
            ubyte[] pureMalloc(size_t size, string file = __FILE__, size_t line = __LINE__) pure @trusted nothrow @nogc
            {
                alias PureM = ubyte[] function(size_t sz, string file = __FILE__, size_t line = __LINE__) pure @nogc @trusted nothrow;
                PureM pureMalloc = cast(PureM)&malloc;
                return pureMalloc(size, file, line);
            }
            pragma(inline, true)
            ubyte[] pureRealloc(ubyte[] ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__) pure @nogc
            {
                alias pRealloc = ubyte[] function (ubyte[], size_t, string file = __FILE__, size_t line = __LINE__) pure @nogc nothrow;
                auto pureRealloc = cast(pRealloc)&realloc;
                return pureRealloc(ptr,newSize,file,line);
            }
            ubyte[] calloc(size_t count, size_t size, string file = __FILE__, size_t line = __LINE__)
            {
                ubyte[] ret =  malloc(count*size, file, line);
                ret[] = 0;
                return ret;
            }

            bool isOnHeap(void* ptr)
            {
                return hookIsOnHeap(ptr) == 1;
            }
        }

    }
}