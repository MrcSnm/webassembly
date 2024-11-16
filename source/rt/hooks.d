module rt.hooks;

version(PSVita) version = UsePSVMem;
version(CustomRuntimeTest) version = UsePSVMem;

version(WebAssembly)
{
    public import core.arsd.memory_allocation;
    import core.stdc.string;
    void abort() pure nothrow @nogc
    {
        static import arsd.webassembly;
        arsd.webassembly.abort();
    }

    /++
        Marks the memory block as OK to append in-place if possible.
    +/
    void assumeSafeAppend(T)(T[] arr) {
        auto block= getAllocatedBlock(arr.ptr);
        if(block is null) assert(0);

        block.used = arr.length;
    }

    /++
        Marks the memory block associated with this array as unique, meaning
        the runtime is allowed to free the old block immediately instead of
        keeping it around for other lingering slices.

        In real D, the GC would take care of this but here I have to hack it.

        arsd.webasm extension
    +/
    void assumeUniqueReference(T)(T[] arr) {
        auto block = getAllocatedBlock(arr.ptr);
        if(block is null) assert(0);

        block.flags |= AllocatedBlock.Flags.unique;
    }

    AllocatedBlock* getAllocatedBlock(void* ptr) pure nothrow
    {
        auto block = (cast(AllocatedBlock*) ptr) - 1;
        if(!block.checkChecksum())
            return null;
        return block;
    }

}
else version(UsePSVMem)
{
    enum MAGIC = ushort.max - 1;
    struct PSVMem
    {
        size_t size;
        ushort magicNumber = MAGIC;
        // string file;
        // size_t line;
        private ubyte[0] data;
        pure nothrow @nogc @trusted void* getPtr () return {return (cast(void*)&this) + PSVMem.sizeof;}
        pragma(inline, true) static uint dataOffset() nothrow pure @nogc @trusted {return PSVMem.sizeof;}
    }

    bool isPSVMem(void* ptr) pure nothrow @nogc @trusted
    {
        if(cast(size_t)ptr <= PSVMem.dataOffset) return false;
        PSVMem mem = *cast(PSVMem*)(ptr - PSVMem.dataOffset);
        return mem.magicNumber == MAGIC;
    }
    void* getPSVMem(void* ptr) pure nothrow @nogc @trusted
    {
        if(ptr is null || !isPSVMem(ptr)) return null;
        return ptr - PSVMem.dataOffset;
    }




    pure nothrow @nogc @trusted
    {
        version(PSVita)
        {
            extern(C) void psv_abort();
            extern(C) void psv_free(ubyte* ptr);
            extern(C) int sceClibPrintf(const(char*) fmt, ...);
            extern(C) ubyte* psv_realloc(ubyte* ptr, size_t newSize);
            extern(C) ubyte* psv_realloc_slice(size_t length, ubyte* ptr, size_t newSize);
            extern(C) ubyte* psv_malloc(size_t sz);
            extern(C) ubyte* psv_calloc(size_t count, size_t newSize);
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

        void abort(){psv_abort();}
        void free(ubyte* ptr) @nogc
        {
            void* thePtr = getPSVMem(ptr);
            if(thePtr !is null) 
                psv_free(cast(ubyte*)thePtr);
        }

        ubyte[] malloc(size_t sz, string file = __FILE__, size_t line = __LINE__) 
        {
            PSVMem* mem  = cast(PSVMem*)psv_malloc(PSVMem.sizeof + sz);
            mem.magicNumber = MAGIC;
            // mem.file = file;
            // mem.line = line;
            mem.size = cast(typeof(mem.size))sz;
            ubyte[] ret = (cast(ubyte*) mem.getPtr)[0..sz];
            return ret;
        }
        ubyte[] realloc(ubyte* ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__)
        {
            void* thePtr = getPSVMem(ptr);
            if(thePtr is null) //Not heap allocated
            {
                //That MUST be a 0 terminated string (we hope it :)
                ubyte* ret = cast(ubyte*)malloc(newSize, file, line).ptr;
                if(!isPSVMem(ret))
                {
                    cast(void)sceClibPrintf("Ptr received is not a PSVMem\nAddr: %p", ptr);
                    psv_abort();
                }
                if(ptr !is null)
                {
                    cast(void)sceClibPrintf("Copied Unknown\n");
                    size_t sz = 0; while(ptr[sz] != '\0') sz++;
                    //Find the initial size
                    memcpy(ret, ptr, sz);
                }
                return ret[0..newSize];
            }
            ///Can't free/use realloc as it will clear memory and runtime copies after realloc.
            ubyte* mem = malloc(newSize).ptr;
            memcpy(mem, ptr, (cast(PSVMem*)thePtr).size);
            return (cast(ubyte*)mem)[0..newSize];
        }

        ubyte[] reallocMain(ubyte[] ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__)
        {
            if(ptr is null) return malloc(newSize, file, line);
            auto thePtr = getPSVMem(ptr.ptr);
            if(thePtr is null)
            {
                auto ret = malloc(newSize, file, line);
                ret[0..ptr.length] = ptr[];
                // cast(void)sceClibPrintf("Copied %.*s\n", cast(uint)ptr.length, cast(char*)ptr.ptr);
                return ret;
            }
            return realloc(ptr.ptr, newSize, file, line);
        }
        pragma(inline, true)
        ubyte[] realloc(ubyte[] ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__)
        {
            return realloc(ptr, newSize, file, line);
        }
        pragma(inline, true)
        ubyte[] pureRealloc(ubyte[] ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__) pure
        {
            alias pRealloc = ubyte[] function (ubyte[], size_t, string file = __FILE__, size_t line = __LINE__) pure @nogc nothrow;
            auto pureRealloc = cast(pRealloc)&reallocMain;
            return pureRealloc(ptr,newSize,file,line);
        }
        ubyte[] calloc(size_t count, size_t size, string file = __FILE__, size_t line = __LINE__)
        {
            ubyte[] ret =  malloc(count*size, file, line);
            ret[] = 0;
            return ret;
        }
    }
}