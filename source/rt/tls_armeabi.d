module rt.tls_armeabi;

// version(ARM):

extern(C) @nogc nothrow pure
{
	/// Set pointer at index in the current thread's TCB (Thread Control Block)
	void rtosbackend_setTLSPointerCurrThread(void* ptr, int index);
	/// Get pointer at index in the current thread's TCB (Thread Control Block)
	void* rtosbackend_getTLSPointerCurrThread(int index);
}

private {
	extern(C) {
		__gshared void* _tdata; /// TLS data (declared in linker script)
		__gshared void* _tdata_size; /// Size of TLS data
		__gshared void* _tbss; /// TLS BSS (declared in linker script)
		__gshared void* _tbss_size; /// Size of TLS BSS
	}

	/// Wrapper around TLS data defined by linker script
	pragma(LDC_no_typeinfo)
	{
		struct TlsLinkerParams
		{
			void* data;
			size_t dataSize;
			void* bss;
			size_t bssSize; 
			size_t fullSize;
		}
	}

	/// Get TLS data defined in linker script
	TlsLinkerParams getTlsLinkerParams() nothrow @nogc 
	{
		TlsLinkerParams param;
		param.data = cast(void*)&_tdata;
		param.dataSize = cast(size_t)&_tdata_size;
		param.bss = cast(void*)&_tbss;
		param.bssSize = cast(size_t)&_tbss_size;
		param.fullSize = param.dataSize + param.bssSize;
		return param;
	}

	/// TCB (Thread Control Block) size as defined by ARM EABI.
	enum ARM_EABI_TCB_SIZE = 8;
}

/// TLS support stores its pointer at index 1 in the TCB (Thread Control Block)
enum tlsPointerIndex = 0;

/// Initialise TLS memory for current thread, return pointer for GC
// void[] initTLSRanges() nothrow @nogc
// {
// 	import rt.hooks;
// 	TlsLinkerParams tls = getTlsLinkerParams;
// 	size_t trueSize = tls.fullSize;
// 	void* memory = malloc(trueSize).ptr;

// 	import core.stdc.string : memcpy, memset;

// 	memset(memory, 0, trueSize);
// 	memcpy(memory, tls.data, tls.dataSize);
// 	memset(memory + tls.dataSize, 0, tls.bssSize);

// 	rtosbackend_setTLSPointerCurrThread(memory, tlsPointerIndex);

// 	return memory[0 .. tls.fullSize];
// }

// /// Free TLS memory for current thread
// void freeTLSRanges() nothrow @nogc
// {
// 	import rt.hooks;
// 	auto memory = rtosbackend_getTLSPointerCurrThread(tlsPointerIndex);
// 	free(cast(ubyte*)memory);
// }

/// Get pointer to TLS memory for current thread. Called internally by compiler whenever a TLS variable is accessed.
// extern(C) void* __aeabi_read_tp() nothrow @nogc
// {
// 	auto ret = rtosbackend_getTLSPointerCurrThread(tlsPointerIndex);
// 	return ret;
// }

//Stubs here

extern(C) void _d_leave_cleanup(void* ptr)
{
}


extern(C) bool _d_enter_cleanup(void* ptr)
{
    // currently just used to avoid that a cleanup handler that can
    // be inferred to not return, is removed by the LLVM optimizer
    //
    // TODO: setup an exception handler here (ptr passes the address
    // of a 40 byte stack area in a parent fuction scope) to deal with
    // unhandled exceptions during unwinding.
    return true;
}
extern(C) void* _d_eh_enter_catch(void* unwindHeader){return null;}
extern(C) int _d_eh_resume_unwind(void* unwindHeader, void* context){assert(false);}
extern(C) int _d_eh_personality(int state, void* unwindHeader,void* context){assert(false);}