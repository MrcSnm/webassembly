module core.internal.cast_;

static if(__VERSION__ <= 2110)
    public import core.internal.cast_v2110;
else
    public import core.internal.cast_v2111;