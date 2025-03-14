module rt.hooks;

version(PSVita) version = UsePSVMem;
version(CustomRuntimeTest) version = UsePSVMem;

version(WebAssembly)
{
    public import core.arsd.memory_allocation;
    void abort() pure nothrow @nogc
    {
        static import arsd.webassembly;
        arsd.webassembly.abort();
    }

}
else version(UsePSVMem)
{
    ///Max is 64 megabytes
    enum MaxSize = 67_108_863;

    pure nothrow @nogc @trusted
    {
        version(PSVita)
        {
            extern(C) void psv_abort();
            extern(C) void psv_free(ubyte* ptr);
            extern(C) int sceClibPrintf(const(char*) fmt, ...);
            extern(C) ubyte* psv_realloc(ubyte* ptr, size_t newSize);
            extern(C) ubyte* psv_malloc(size_t sz);
            extern(C) ubyte* psv_calloc(size_t count, size_t newSize);
            extern(C) int psv_isOnHeap(void* ptr);
            extern(C) size_t psv_get_allocated_memory();
        }
        else
        {
            extern(C)
            {
                void exit(int exitCode);
                void psv_abort()
                {
                    asm pure @nogc nothrow {int 3;}
                    exit(-1);
                }
                pragma(mangle, "free") void psv_free(ubyte* ptr);
                pragma(mangle, "realloc") ubyte* psv_realloc(ubyte* ptr, size_t newSize);
                pragma(mangle, "malloc") ubyte* psv_malloc(size_t sz);
                pragma(mangle, "calloc") ubyte* psv_calloc(size_t count, size_t newSize);
                pragma(mangle, "printf") int sceClibPrintf(const(char*) fmt, ...);
            }
        }

        size_t getMemoryAllocated()
        {
            return psv_get_allocated_memory();
        }

        void abort(){psv_abort();}
        void free(ubyte* ptr, string file, size_t line) @nogc
        {
            psv_free(ptr);
        }

        ubyte[] malloc(size_t sz, string file = __FILE__, size_t line = __LINE__) 
        {
            return psv_malloc(sz)[0..sz];
        }
        ubyte[] realloc(ubyte* ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__)
        {
            return psv_realloc(ptr, newSize)[0..newSize];
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
            return psv_isOnHeap(ptr) == 1;
        }
    }
}