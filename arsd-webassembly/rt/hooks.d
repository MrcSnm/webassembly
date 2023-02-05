module rt.hooks;

version(WebAssembly)
{
    void abort() pure nothrow @nogc
    {
        static import arsd.webassembly;
        arsd.webassembly.abort();
    }
    
    // ldc defines this, used to find where wasm memory begins
    private extern extern(C) ubyte __heap_base;
    //                                           ---unused--- -- stack grows down -- -- heap here --
    // this is less than __heap_base. memory map 0 ... __data_end ... __heap_base ... end of memory
    private extern extern(C) ubyte __data_end;

    // llvm intrinsics {
        /+
            mem must be 0 (it is index of memory thing)
            delta is in 64 KB pages
            return OLD size in 64 KB pages, or size_t.max if it failed.
        +/
        pragma(LDC_intrinsic, "llvm.wasm.memory.grow.i32")
        private int llvm_wasm_memory_grow(int mem, int delta);


        // in 64 KB pages
        pragma(LDC_intrinsic, "llvm.wasm.memory.size.i32")
        private int llvm_wasm_memory_size(int mem);
    // }



    private __gshared ubyte* nextFree;
    private __gshared size_t memorySize; // in units of 64 KB pages

    align(16)
    private struct AllocatedBlock {
        enum Magic = 0x731a_9bec;
        enum Flags {
            inUse = 1,
            unique = 2,
        }

        size_t blockSize;
        size_t flags;
        size_t magic;
        size_t checksum;

        size_t used; // the amount actually requested out of the block; used for assumeSafeAppend

        /* debug */
        string file;
        size_t line;

        // note this struct MUST align each alloc on an 8 byte boundary or JS is gonna throw bullshit

        void populateChecksum() {
            checksum = blockSize ^ magic;
        }

        bool checkChecksum() const @nogc {
            return magic == Magic && checksum == (blockSize ^ magic);
        }

        ubyte[] dataSlice() return {
            return ((cast(ubyte*) &this) + typeof(this).sizeof)[0 .. blockSize];
        }

        static int opApply(scope int delegate(AllocatedBlock*) dg) {
            if(nextFree is null)
                return 0;
            ubyte* next = &__heap_base;
            AllocatedBlock* block = cast(AllocatedBlock*) next;
            while(block.checkChecksum()) {
                if(auto result = dg(block))
                    return result;
                next += AllocatedBlock.sizeof;
                next += block.blockSize;
                block = cast(AllocatedBlock*) next;
            }

            return 0;
        }
    }

    static assert(AllocatedBlock.sizeof % 16 == 0);

    void free(ubyte* ptr) @nogc {
        auto block = (cast(AllocatedBlock*) ptr) - 1;
        if(!block.checkChecksum())
            assert(false, "Could not check block on free");

        block.used = 0;
        block.flags = 0;

        // last one
        if(ptr + block.blockSize == nextFree) {
            nextFree = cast(ubyte*) block;
            assert(cast(size_t)nextFree % 16 == 0);
        }
    }

    ubyte[] realloc(ubyte* ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__) {
        if(ptr is null)
            return malloc(newSize, file, line);

        auto block = (cast(AllocatedBlock*) ptr) - 1;
        if(!block.checkChecksum())
            assert(false, "Could not check block while realloc");

        // block.populateChecksum();
        if(newSize <= block.blockSize) {
            block.used = newSize;
            return ptr[0 .. newSize];
        } else {
            // FIXME: see if we can extend teh block into following free space before resorting to malloc

            if(ptr + block.blockSize == nextFree) {
                while(growMemoryIfNeeded(newSize)) {}

                size_t blockSize = newSize;
                if(const over = blockSize % 16)
                    blockSize+= 16 - over;

                block.blockSize = blockSize;
                block.used = newSize;
                block.populateChecksum();
                nextFree = ptr + block.blockSize;
                assert(cast(size_t)nextFree % 16 == 0);
                return ptr[0 .. newSize];
            }

            auto newThing = malloc(newSize);
            newThing[0 .. block.used] = ptr[0 .. block.used];

            if(block.flags & AllocatedBlock.Flags.unique) {
                // if we do malloc, this means we are allowed to free the existing block
                free(ptr);
            }

            assert(cast(size_t) newThing.ptr % 16 == 0);

            return newThing;
        }
    }

    /**
    *  If the ptr isn't owned by the runtime, it will completely malloc the data (instead of realloc)
    *   and copy its old content.
    */
    ubyte[] realloc(ubyte[] ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__)
    {
        if(ptr is null)
            return malloc(newSize, file, line);
        auto block = (cast(AllocatedBlock*) ptr) - 1;
        if(!block.checkChecksum())
        {
            auto ret = malloc(newSize, file, line);
            ret[0..ptr.length] = ptr[]; //Don't clear ptr memory as it can't be clear.
            return ret;
        }
        else return realloc(ptr.ptr, newSize, file, line);

    }

    private bool growMemoryIfNeeded(size_t sz) {
        if(cast(size_t) nextFree + AllocatedBlock.sizeof + sz >= memorySize * 64*1024) {
            if(llvm_wasm_memory_grow(0, 4) == size_t.max)
                assert(0, "Out of memory"); // out of memory

            memorySize = llvm_wasm_memory_size(0);

            return true;
        }

        return false;
    }
    
    ubyte[] malloc(size_t sz, string file = __FILE__, size_t line = __LINE__) {
        // lol bumping that pointer
        if(nextFree is null) {
            nextFree = &__heap_base; // seems to be 75312
            assert(cast(size_t)nextFree % 16 == 0);
            memorySize = llvm_wasm_memory_size(0);
        }

        while(growMemoryIfNeeded(sz)) {}

        auto base = cast(AllocatedBlock*) nextFree;

        auto blockSize = sz;
        if(auto val = blockSize % 16)
        blockSize += 16 - val; // does NOT include this metadata section!

        // debug list allocations
        //import std.stdio; writeln(file, ":", line, " / ", sz, " +", blockSize);

        base.blockSize = blockSize;
        base.flags = AllocatedBlock.Flags.inUse;
        // these are just to make it more reliable to detect this header by backtracking through the pointer from a random array.
        // otherwise it'd prolly follow the linked list from the beginning every time or make a free list or something. idk tbh.
        base.magic = AllocatedBlock.Magic;
        base.populateChecksum();

        base.used = sz;

        // debug
        base.file = file;
        base.line = line;

        nextFree += AllocatedBlock.sizeof;

        auto ret = nextFree;

        nextFree += blockSize;

        //writeln(cast(size_t) nextFree);
        //import std.stdio; writeln(cast(size_t) ret, " of ", sz, " rounded to ", blockSize);
        //writeln(file, ":", line);
        assert(cast(size_t) ret % 8 == 0);

        return ret[0 .. sz];
    }

    
    ubyte[] calloc(size_t count, size_t size, string file = __FILE__, size_t line = __LINE__) 
    {
        auto ret = malloc(count*size,file,line);
        ret[0..$] = 0;
        return ret;
    }


    // debug
    export extern(C) void printBlockDebugInfo(void* ptr) {
        if(ptr is null) {
            foreach(block; AllocatedBlock) {
                printBlockDebugInfo(block);
            }
            return;
        }

        // otherwise assume it is a pointer returned from malloc

        auto block = (cast(AllocatedBlock*) ptr) - 1;
        if(ptr is null)
            block = cast(AllocatedBlock*) &__heap_base;

        printBlockDebugInfo(block);
    }

    // debug
    void printBlockDebugInfo(AllocatedBlock* block) {
        import std.stdio;
        writeln(block.blockSize, " ", block.flags, " ", block.checkChecksum() ? "OK" : "X", " ");
        if(block.checkChecksum())
            writeln(cast(size_t)((cast(ubyte*) (block + 2)) + block.blockSize), " ", block.file, " : ", block.line);
    }

    export extern(C) ubyte* bridge_malloc(size_t sz) {
        return malloc(sz).ptr;
    }
    
    AllocatedBlock* getAllocatedBlock(void* ptr) {
        auto block = (cast(AllocatedBlock*) ptr) - 1;
        if(!block.checkChecksum())
            return null;
        return block;
    }

    /++
        Marks the memory block as OK to append in-place if possible.
    +/
    void assumeSafeAppend(T)(T[] arr) {
        auto block = getAllocatedBlock(arr.ptr);
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

}
else version(PSVita)
{
    pure nothrow @nogc @trusted
    {
        extern(C) void psv_abort();
        extern(C) void psv_free(ubyte* ptr);
        extern(C) ubyte* psv_realloc(ubyte* ptr, size_t newSize);
        extern(C) ubyte* psv_malloc(size_t sz);
        extern(C) ubyte* psv_calloc(size_t count, size_t newSize);

        void abort(){psv_abort();}
        void free(ubyte* ptr) @nogc{psv_free(ptr);}
        ubyte[] realloc(ubyte* ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__){return psv_realloc(ptr, newSize)[0..newSize];}
        ubyte[] realloc(ubyte[] ptr, size_t newSize, string file = __FILE__, size_t line = __LINE__){return psv_realloc(ptr.ptr, newSize)[0..newSize];}
        ubyte[] malloc(size_t sz, string file = __FILE__, size_t line = __LINE__) {return psv_malloc(sz)[0..sz];}
        ubyte[] calloc(size_t count, size_t size, string file = __FILE__, size_t line = __LINE__){return psv_calloc(count, size)[0..count*size];}

    }
}