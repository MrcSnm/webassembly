module core.array.setlength_v2111;

static if(__VERSION__ >= 2111):
/**
Resize a dynamic array by setting its `.length` property.

Newly created elements are initialized based on their default value.
If the array's elements initialize to `0`, memory is zeroed out. Otherwise, elements are explicitly initialized.

This function handles memory allocation, expansion, and initialization while maintaining array integrity.

---
void main()
{
    int[] a = [1, 2];
    a.length = 3; // Gets lowered to `_d_arraysetlengthT!(int)(a, 3, false)`
}
---

Params:
    arr         = The array to resize.
    newlength   = The new value for the array's `.length`.

Returns:
    The resized array with updated length and properly initialized elements.

Throws:
    OutOfMemoryError if allocation fails.
*/
size_t _d_arraysetlengthT(Tarr : T[], T)(return ref scope Tarr arr, size_t newlength) @trusted
{
    import core.internal.traits : Unqual;

    // Check if the type is shared
    enum isShared = is(T == shared);

    // Unqualify the type to remove `const`, `immutable`, `shared`, etc.
    alias UnqT = Unqual!T;

    // Cast the array to the unqualified type
    auto unqual_arr = cast(UnqT[]) arr;

    // Call the implementation with the unqualified array and sharedness flag
    size_t result = _d_arraysetlengthT_(unqual_arr, newlength, isShared);

    arr = cast(Tarr) unqual_arr;
    // Return the result
    return result;
}

private size_t _d_arraysetlengthT_(Tarr : T[], T)(return ref scope Tarr arr, size_t newlength, bool isShared) @trusted pure
{
    import core.checkedint : mulu;
    import core.exception : onFinalizeError, onOutOfMemoryError;
    import core.arsd.objectutils;
    import core.stdc.string : memcpy, memset;
    import core.internal.traits : hasElaborateCopyConstructor, Unqual;
    import core.lifetime : emplace;
    import core.memory;
    import rt.hooks;
    import core.internal.lifetime : __doPostblit;
    alias UnqT = Unqual!T;

    // If the new length is less than or equal to the current length, just truncate the array
    if (newlength <= arr.length)
    {
        arr = arr[0 .. newlength];
        return newlength;
    }

    enum sizeelem = T.sizeof;
    enum hasPostblit = __traits(hasMember, T, "__postblit");
    enum hasEnabledPostblit = hasPostblit && !__traits(isDisabled, T.__postblit);

    bool overflow = false;
    const newsize = mulu(sizeelem, newlength, overflow);
    if (overflow)
    {
        onOutOfMemoryError();
        assert(0);
    }

    if (!arr.ptr)
    {
        // pointer was null, need to allocate
        auto info = pureMalloc(newsize);
        static if (__traits(isZeroInit, T))
           memset(info.ptr, 0, newsize);
        else static if (hasElaborateCopyConstructor!T && !hasPostblit)
        {
            foreach (i; 0 .. newlength)
                emplace(cast(UnqT*) info.ptr + i, UnqT.init); // safe default construction
        }
        else
        {
            auto temp = UnqT.init;
            foreach (i; 0 .. newlength)
                memcpy(cast(UnqT*) info.ptr + i, cast(const void*)&temp, T.sizeof);

            static if (hasEnabledPostblit)
                __doPostblit!T((cast(T*) info.ptr)[0 .. newlength]);

        }
        arr = (cast(T*)info)[0 .. newlength];
        return newlength;
    }

    size_t oldsize = arr.length * sizeelem;
    auto ret = pureRealloc(cast(ubyte[])arr, newsize);

    if(ret.ptr != cast(ubyte*)arr.ptr)
        ret[0 .. oldsize] = cast(ubyte[])arr.ptr[0 .. oldsize];

    auto newdata = cast(void*) arr.ptr;

    // Handle initialization based on whether the type requires zero-init
    static if (__traits(isZeroInit, T))
        memset(cast(void*) (cast(ubyte*)newdata + oldsize), 0, newsize - oldsize);
    else static if (hasElaborateCopyConstructor!T && !hasPostblit)
    {
        foreach (i; 0 .. newlength - arr.length)
            emplace(cast(UnqT*) (cast(ubyte*)newdata + oldsize) + i, UnqT.init);
    }
    else
    {
        auto temp = UnqT.init;
        foreach (i; 0 .. newlength - arr.length)
            memcpy(cast(UnqT*) (cast(ubyte*)newdata + oldsize) + i, cast(const void*)&temp, T.sizeof);

        static if (hasEnabledPostblit)
            __doPostblit!T((cast(T*) (cast(ubyte*)newdata + oldsize))[0 .. newlength - arr.length]);
    }

    arr = (cast(T*) newdata)[0 .. newlength];
    return newlength;
}