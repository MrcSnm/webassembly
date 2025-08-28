module core.array.setlength_v2110;

static if(__VERSION__ <= 2110):

template _d_arraysetlengthTImpl(Tarr : T[], T) {
	size_t _d_arraysetlengthT(return scope ref Tarr arr, size_t newlength) @trusted pure {

		if(newlength <= arr.length) {
			arr = arr[0 ..newlength];
		} else {
			auto ptr = cast(T*) pureRealloc(cast(ubyte[])arr, newlength * T.sizeof);
			arr = ptr[0 .. newlength];
		}

		return newlength;
	}
}

extern (C) void[] _d_arraysetlengthT(const TypeInfo ti, size_t newlength, void[]* p)
in
{
    assert(ti);
    assert(!(*p).length || (*p).ptr);
}
do
{
    import core.arsd.objectutils;
    if (newlength <= (*p).length)
    {
        *p = (*p)[0 .. newlength];
        void* newdata = (*p).ptr;
        return newdata[0 .. newlength];
    }
    auto tinext = ti.next;
    size_t sizeelem = tinext.size;

    /* Calculate: newsize = newlength * sizeelem
     */
    bool overflow = false;
    import core.checkedint : mulu;
    const size_t newsize = mulu(sizeelem, newlength, overflow);
    if (overflow)
        onOutOfMemoryError();

    if (!(*p).ptr)
    {
        // pointer was null, need to allocate
        auto info = malloc(newsize);
        memset(info.ptr, 0, newsize);
        *p = info[0 .. newlength];
        return *p;
    }

    const size_t size = (*p).length * sizeelem;

    /* Attempt to extend past the end of the existing array.
     * If not possible, allocate new space for entire array and copy.
     */
    auto ptr = pureRealloc(cast(ubyte[])*p, newsize);
    ptr[0 .. size] = cast(ubyte[])p.ptr[0 .. size];

    /* Do postblit processing, as we are making a copy and the
    * original array may have references.
    * Note that this may throw.
    */
    __doPostblit(p.ptr, size, tinext);

    // Initialize the unused portion of the newly allocated space
    memset(p.ptr + size, 0, newsize - size);
    return *p;
}

extern (C) void[] _d_arraysetlengthiT(const TypeInfo ti, size_t newlength, void[]* p)
in
{
    assert(!(*p).length || (*p).ptr);
}
do
{
    import core.arsd.objectutils;
    if (newlength <= (*p).length)
    {
        *p = (*p)[0 .. newlength];
        void* newdata = (*p).ptr;
        return newdata[0 .. newlength];
    }
    auto tinext = ti.next;
    size_t sizeelem = tinext.size;

    import core.checkedint : mulu;
    bool overflow;
    const size_t newsize = mulu(sizeelem, newlength, overflow);
    if (overflow)
        onOutOfMemoryError();

    static void doInitialize(void *start, void *end, const void[] initializer)
    {
        if (initializer.length == 1)
        {
            memset(start, *(cast(ubyte*)initializer.ptr), end - start);
        }
        else
        {
            auto q = initializer.ptr;
            immutable initsize = initializer.length;
            for (; start < end; start += initsize)
            {
                memcpy(start, q, initsize);
            }
        }
    }

    if (!(*p).ptr)
    {
        // pointer was null, need to allocate
        auto info = malloc(newsize);
        doInitialize(info.ptr, info.ptr + newsize, tinext.initializer);
        *p = info[0 .. newlength];
        return *p;
    }

    const size_t size = (*p).length * sizeelem;

    /* Attempt to extend past the end of the existing array.
     * If not possible, allocate new space for entire array and copy.
     */
    auto ptr = pureRealloc(cast(ubyte[])*p, newsize);
    ptr[0 .. size] = cast(ubyte[])p.ptr[0 .. size];

    /* Do postblit processing, as we are making a copy and the
    * original array may have references.
    * Note that this may throw.
    */
    __doPostblit(p.ptr, size, tinext);

    // Initialize the unused portion of the newly allocated space
    doInitialize(p.ptr + size, p.ptr + newsize, tinext.initializer);
    return *p;
}


// extern(C) void[] _d_arraysetlengthiT(const TypeInfo ti, size_t newlength, void[]* p)
// {

// }
