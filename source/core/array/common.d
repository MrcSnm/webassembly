module core.array.common;
static import rt.hooks;
// import rt.hooks : free, malloc, calloc, realloc, pureRealloc;

extern (C) byte[] _d_arrayappendcTX(const TypeInfo ti, ref byte[] px, size_t n) @trusted nothrow 
{
	auto elemSize = ti.next.size;
	auto newLength = n + px.length;
	auto newSize = newLength * elemSize;
	//import std.stdio; writeln(newSize, " ", newLength);
	ubyte* ptr;
    bool hasReallocated = false;
	if(px.ptr is null)
		ptr = rt.hooks.malloc(newSize).ptr;
	else
    {
        // FIXME: anti-stomping by checking length == used   
        hasReallocated = true;
		ptr = rt.hooks.realloc(cast(ubyte[])px, newSize).ptr;
    }
	auto ns = ptr[0 .. newSize];
	auto op = px.ptr;
	auto ol = px.length * elemSize;

	foreach(i, b; op[0 .. ol])
		ns[i] = b;

    version(PSVita)
    {
        if(hasReallocated)
            rt.hooks.free(cast(ubyte*)op);
    }

	(cast(size_t *)(&px))[0] = newLength;
	(cast(void **)(&px))[1] = ns.ptr;
	return px;
}