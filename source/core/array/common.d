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
	bool isHeapAllocated = true;
	isHeapAllocated = rt.hooks.isOnHeap(px.ptr) == 1;


	if(px.ptr is null || !isHeapAllocated)
	{
		ptr = rt.hooks.malloc(newSize).ptr;
		auto ns = ptr[0 .. newSize];
		auto op = px.ptr;
		auto ol = px.length * elemSize;

		foreach(i, b; op[0 .. ol])
			ns[i] = b;
	}
	else
    {
        // FIXME: anti-stomping by checking length == used
		ptr = rt.hooks.realloc(cast(ubyte[])px, newSize).ptr;
    }

	(cast(size_t *)(&px))[0] = newLength;
	(cast(void **)(&px))[1] = ptr;
	return px;
}