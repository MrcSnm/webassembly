module core.internal.cast_v2110;

static if(__VERSION__ <= 2110):

extern(C) void* _d_dynamic_cast(Object o, TypeInfo_Class c) {
	void* res = null;
	size_t offset = 0;
	if (o && _d_isbaseof2(typeid(o), c, offset))
	{
		res = cast(void*) o + offset;
	}
	return res;
}

/*****
 * Dynamic cast from a class object o to class c, where c is a subclass of o.
 * Params:
 *      o = instance of class
 *      c = a subclass of o
 * Returns:
 *      null if o is null or c is not a subclass of o. Otherwise, return o.
 */
void* _d_class_cast(Object o, TypeInfo_Class c)
{
    if (!o)
        return null;
    
    // Needed because ClassInfo.opEquals(Object) does a dynamic cast,
    // but we are trying to implement dynamic cast.
    static bool areClassInfosEqual(scope const TypeInfo_Class a, scope const TypeInfo_Class b) @safe
    {
        // same class if signatures match, works with potential duplicates across binaries
        return a is b ||
            (a.flags & 0x200 /*TypeInfo_Class.ClassFlags.hasNameSig*/
            ? (a.nameSig[0] == b.nameSig[0] &&
            a.nameSig[1] == b.nameSig[1])  // new fast way
            : (a is b || a.name == b.name));  // old slow way for temporary binary compatibility
    }


    TypeInfo_Class oc = typeid(o);
    int delta = oc.depth;

    if (delta && c.depth)
    {
        delta -= c.depth;
        if (delta < 0)
            return null;

        while (delta--)
            oc = oc.base;
        if (areClassInfosEqual(oc, c))
            return cast(void*)o;
        return null;
    }

    // no depth data - support the old way
    do
    {
        if (areClassInfosEqual(oc, c))
            return cast(void*)o;
        oc = oc.base;
    } while (oc);
    return null;
}

/*************************************
 * Attempts to cast Object o to class c.
 * Returns o if successful, null if not.
 */
extern(C) void* _d_interface_cast(void* p, TypeInfo_Class c)
{
    if (!p)
        return null;

    Interface* pi = **cast(Interface***) p;
    return _d_dynamic_cast(cast(Object)(p - pi.offset), c);
}


extern(C)
int _d_isbaseof2(scope TypeInfo_Class oc, scope const TypeInfo_Class c, scope ref size_t offset) @safe

{
    if (oc is c)
        return true;

    do
    {
        if (oc.base is c)
            return true;

        // Bugzilla 2013: Use depth-first search to calculate offset
        // from the derived (oc) to the base (c).
        foreach (iface; oc.interfaces)
        {
            if (iface.classinfo is c || _d_isbaseof2(iface.classinfo, c, offset))
            {
                offset += iface.offset;
                return true;
            }
        }

        oc = oc.base;
    } while (oc);

    return false;
}
