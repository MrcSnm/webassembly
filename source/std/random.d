module std.random;


int uniform(int low, int high) 
{
	version(PSVita)
	{
		return 0;
	}
	else
	{
		import arsd.webassembly;
		int max = high - low;
		return low + eval!int(q{ return Math.floor(Math.random() * $0); }, max);
	}
}
