module core.array.assign;

// Force `enforceRawArraysConformable` to remain `pure` `@nogc`
private void enforceRawArraysConformable(const char[] action, const size_t elementSize,
    const void[] a1, const void[] a2, const bool allowOverlap) @trusted @nogc pure nothrow
{
    import core.array.util : enforceRawArraysConformableNogc;

    alias Type = void function(const char[] action, const size_t elementSize,
        const void[] a1, const void[] a2, in bool allowOverlap = false) @nogc pure nothrow;
    (cast(Type)&enforceRawArraysConformableNogc)(action, elementSize, a1, a2, allowOverlap);
}

private template CopyElem(string CopyAction)
{
    const char[] CopyElem = "{\n" ~ q{
            memcpy(&tmp, cast(void*) &dst, elemSize);
            } ~ CopyAction ~ q{
            auto elem = cast(Unqual!T*) &tmp;
            destroy(*elem);
        } ~ "}\n";
}

private template CopyArray(bool CanOverlap, string CopyAction)
{
    const char[] CopyArray = CanOverlap ? q{
        if (vFrom.ptr < vTo.ptr && vTo.ptr < vFrom.ptr + elemSize * vFrom.length)
            foreach_reverse (i, ref dst; to)
            } ~ CopyElem!(CopyAction) ~ q{
        else
            foreach (i, ref dst; to)
            } ~ CopyElem!(CopyAction)
        : q{
            foreach (i, ref dst; to)
            } ~ CopyElem!(CopyAction);
}

private template ArrayAssign(string CopyLogic, string AllowOverLap)
{
    const char[] ArrayAssign = q{
        import core.internal.traits : hasElaborateCopyConstructor, Unqual;
        import core.lifetime : copyEmplace;
        import core.stdc.string : memcpy;

        void[] vFrom = (cast(void*) from.ptr)[0 .. from.length];
        void[] vTo = (cast(void*) to.ptr)[0 .. to.length];
        enum elemSize = T.sizeof;

        enforceRawArraysConformable("copy", elemSize, vFrom, vTo, } ~ AllowOverLap ~ q{);

        void[elemSize] tmp = void;

        } ~ CopyLogic ~ q{

        return to;
    };
}

Tarr _d_arrayassign_l(Tarr : T[], T)(return scope Tarr to, scope Tarr from) @trusted
{
    mixin(ArrayAssign!(q{
        static if (hasElaborateCopyConstructor!T)
            } ~ CopyArray!(true, "copyEmplace(from[i], dst);") ~ q{
        else
            } ~ CopyArray!(true, "memcpy(cast(void*) &dst, cast(void*) &from[i], elemSize);"),
        "true"));
}

Tarr _d_arrayassign_r(Tarr : T[], T)(return scope Tarr to, scope Tarr from) @trusted
{
    mixin(ArrayAssign!(
        CopyArray!(false, "memcpy(cast(void*) &dst, cast(void*) &from[i], elemSize);"),
        "false"));
}

Tarr _d_arraysetassign(Tarr : T[], T)(return scope Tarr to, scope ref T value) @trusted
{
    import core.internal.traits : Unqual;
    import core.lifetime : copyEmplace;
    //import core.stdc.string : memcpy;

    enum elemSize = T.sizeof;
    void[elemSize] tmp = void;

    foreach (ref dst; to)
    {
        memcpy(&tmp, cast(void*) &dst, elemSize);
        // Use `memcpy` if `T` has a `@disable`d postblit.
        static if (__traits(isCopyable, T))
            copyEmplace(value, dst);
        else
            memcpy(cast(void*) &dst, cast(void*) &value, elemSize);
        auto elem = cast(Unqual!T*) &tmp;
        destroy(*elem);
    }

    return to;
}