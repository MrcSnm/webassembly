module core.internal.cast_v2111;

static if(__VERSION__ >= 2111):

/*****
 * Dynamic cast from a class object `o` to class or interface `To`, where `To` is a subtype of `o`.
 * Params:
 *      o = instance of class
 *      To = class or interface that is a subtype of `o`
 * Returns:
 *      null if `o` is null or `To` is not a subclass type of `o`. Otherwise, return `o`.
 */
private void* _d_dynamic_cast(To)(const return scope Object o) @trusted
{
    void* res = null;
    size_t offset = 0;

    if (o && _d_isbaseof2!To(typeid(o), offset))
    {
        res = cast(void*) o + offset;
    }
    return res;
}

/**
 * Dynamic cast `o` to final class `To` only one level down
 * Params:
 *      o = object that is instance of a class
 *      To = final class that is a subclass type of `o`
 * Returns:
 *      o if it succeeds, null if it fails
 */
private void* _d_paint_cast(To)(const return scope Object o)
{
    /* If o is really an instance of c, just do a paint
     */
    auto p = o && cast(void*)(areClassInfosEqual(typeid(o), typeid(To).info)) ? o : null;
    debug assert(cast(void*)p is cast(void*)_d_dynamic_cast!To(o));
    return cast(void*)p;
}


/*****
 * Dynamic cast from a class object o to class type `To`, where `To` is a subclass type of `o`.
 * Params:
 *      o = instance of class
 *      To = a subclass type of o
 * Returns:
 *      null if `o` is null or `To` is not a subclass type of `o`. Otherwise, return `o`.
 */
private void* _d_class_cast(To)(const return scope Object o)
{
    return _d_class_cast_impl(o, typeid(To));
}

/*************************************
 * Attempts to cast interface Object o to class type `To`.
 * Returns o if successful, null if not.
 */
private void* _d_interface_cast(To)(void* p) @trusted
{
    if (!p)
        return null;

    Interface* pi = **cast(Interface***) p;

    Object o2 = cast(Object)(p - pi.offset);
    void* res = null;
    size_t offset = 0;
    if (o2 && _d_isbaseof2!To(typeid(o2), offset))
    {
        res = cast(void*) o2 + offset;
    }
    return res;
}

/**
* Hook that detects the type of cast performed and calls the appropriate function.
* Params:
*      o = object that is being casted
*      To = type to which the object is being casted
* Returns:
*      null if the cast fails, otherwise returns the object casted to the type `To`.
*/
void* _d_cast(To, From)(From o) @trusted
{
    static if (is(From == class) && is(To == interface))
    {
        return _d_dynamic_cast!To(o);
    }

    static if (is(From == class) && is(To == class))
    {
        static if (is(From FromSupers == super) && is(To ToSupers == super))
        {
            /* Check for:
            *  class A { }
            *  final class B : A { }
            *  ... cast(B) A ...
            */
            // Multiple inheritance is not allowed, so we can safely assume
            // that the second super can only be an interface.
            static if (__traits(isFinalClass, To) && is(ToSupers[0] == From) &&
                       ToSupers.length == 1 && FromSupers.length <= 1)
            {
                return _d_paint_cast!To(o);
            }
        }

        static if (is (To : From))
        {
            static if (is (To == From))
            {
                return cast(void*)o;
            }
            else
            {
                return _d_class_cast!To(o);
            }
        }

        return null;
    }

    static if (is(From == interface))
    {
        static if (is(From == To))
        {
            return cast(void*)o;
        }
        else
        {
            return _d_interface_cast!To(cast(void*)o);
        }
    }
    else
    {
        return null;
    }
}

private bool _d_isbaseof2(To)(scope TypeInfo_Class oc, scope ref size_t offset)
{
    auto c = typeid(To).info;

    if (areClassInfosEqual(oc, c))
        return true;

    do
    {
        if (oc.base && areClassInfosEqual(oc.base, c))
            return true;

        // Bugzilla 2013: Use depth-first search to calculate offset
        // from the derived (oc) to the base (c).
        foreach (iface; oc.interfaces)
        {
            if (areClassInfosEqual(iface.classinfo, c) || _d_isbaseof2!To(iface.classinfo, offset))
            {
                offset += iface.offset;
                return true;
            }
        }

        oc = oc.base;
    } while (oc);

    return false;
}
