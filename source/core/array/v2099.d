module core.array.v2099;
import rt.hooks;
import core.array.common;

extern (C) void[] _d_arrayappendT(const TypeInfo ti, ref byte[] x, byte[] y)
{
    auto length = x.length;
    auto tinext = ti.next;
    auto sizeelem = tinext./*t*/size;              // array element size
    _d_arrayappendcTX(ti, x, y.length);
    memcpy(x.ptr + length * sizeelem, y.ptr, y.length * sizeelem);

    // do postblit
    //__doPostblit(x.ptr + length * sizeelem, y.length * sizeelem, tinext);
    return x;
}