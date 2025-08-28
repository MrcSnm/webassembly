module core.array.setlength;

static if(__VERSION__ <= 2110)
    public import core.array.setlength_v2110;
else
    public import core.array.setlength_v2111;