module core.array.v2102;
public import core.array.common;
import core.internal.traits;
import rt.hooks;

template _d_arrayappendcTXImpl(Tarr: T[], T)
{
    alias _d_arrayappendcTX = ._d_arrayappendcTX!(Tarr, T);
}


ref Tarr _d_arrayappendcTX(Tarr: T[], T)(return ref scope Tarr px, size_t n) @trusted nothrow pure
{
    // needed for CTFE: https://github.com/dlang/druntime/pull/3870#issuecomment-1178800718
    pragma(inline, false);
    auto ti = typeid(Tarr);

    alias pureArrayAppendcTX =  extern(C) @trusted nothrow pure byte[] function(const TypeInfo ti, ref byte[] px, size_t n);

    auto arrayAppendcTX = cast(pureArrayAppendcTX)&core.array.common._d_arrayappendcTX;

    // _d_arrayappendcTX takes the `px` as a ref byte[], but its length
    // should still be the original length
    auto pxx = (cast(byte*)px.ptr)[0 .. px.length];
    arrayAppendcTX(ti, pxx, n);
    px = (cast(T*)pxx.ptr)[0 .. pxx.length];

    return px;
}

ref Tarr _d_arrayappendT(Tarr : T[], T)(return ref scope Tarr x, scope Tarr y) @trusted pure
{
    auto length = x.length;


    alias pure_d_arrayappendcTX = pure nothrow @trusted ref Tarr function(return ref scope Tarr px, size_t n);
    auto arrayAppendcTX = cast(pure_d_arrayappendcTX)&_d_arrayappendcTX!Tarr;

    arrayAppendcTX(x, y.length);
    memcpy(cast(Unqual!T*)x.ptr + length * T.sizeof, y.ptr, y.length * T.sizeof);

    // do postblit
    //__doPostblit(x.ptr + length * sizeelem, y.length * sizeelem, tinext);
    return x;
}    

