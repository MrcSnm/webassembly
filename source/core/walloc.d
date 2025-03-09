module core.walloc;

// walloc.c: a small malloc implementation for use in WebAssembly targets
// Copyright (c) 2020 Igalia, S.L.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

alias uintptr_t = uint*;
alias uint8_t = ubyte;
import ldc.intrinsics;

@nogc nothrow:

pragma(inline, true) size_t max(size_t a, size_t b) {return a < b ? b : a;}

private pragma(inline, true) uintptr_t align_(uintptr_t val, uintptr_t alignment)
{
  return cast(uintptr_t)((cast(size_t)val + cast(size_t)alignment - 1) & ~(cast(size_t)alignment - 1));
}
void assert_aligned(uintptr_t x, uintptr_t y)
{
    assert(x == align_(x, y));
}
void assert_aligned(uintptr_t x, int y)
{
    assert(x == align_(x, cast(uintptr_t)y));
}
void assert_aligned(uint x, int y)
{
    assert(cast(uintptr_t)x == cast(uintptr_t)align_(cast(uintptr_t)x, cast(uintptr_t)y));
}


enum CHUNK_SIZE = 256;
enum CHUNK_SIZE_LOG_2 = 8;
enum CHUNK_MASK = (CHUNK_SIZE - 1);
static assert(CHUNK_SIZE == 1 << CHUNK_SIZE_LOG_2);

enum PAGE_SIZE =  65536;
enum PAGE_SIZE_LOG_2 =  16;
enum PAGE_MASK =  (PAGE_SIZE - 1);
static assert(PAGE_SIZE == 1 << PAGE_SIZE_LOG_2);

enum CHUNKS_PER_PAGE = 256;
static assert(PAGE_SIZE == CHUNK_SIZE * CHUNKS_PER_PAGE);

enum GRANULE_SIZE =  8;
enum GRANULE_SIZE_LOG_2 =  3;
enum LARGE_OBJECT_THRESHOLD =  256;
enum LARGE_OBJECT_GRANULE_THRESHOLD =  32;

static assert (GRANULE_SIZE == 1 << GRANULE_SIZE_LOG_2);
static assert (LARGE_OBJECT_THRESHOLD ==
                 LARGE_OBJECT_GRANULE_THRESHOLD * GRANULE_SIZE);

struct chunk {
  char[CHUNK_SIZE] data;
}

//FOR_EACH_SMALL_OBJECT_GRANULES
// There are small object pages for allocations of these sizes.
immutable int[] SMALL_OBJECT_GRANULES = [1, 2, 3, 4, 5, 6, 8, 10, 16, 32];

enum chunk_kind
{
  // #define FOR_EACH_SMALL_OBJECT_GRANULES(M) \
  //   M(1) M(2) M(3) M(4) M(5) M(6) M(8) M(10) M(16) M(32)
    GRANULES_1,
    GRANULES_2,
    GRANULES_3,
    GRANULES_4,
    GRANULES_5,
    GRANULES_6,
    GRANULES_8,
    GRANULES_10,
    GRANULES_16,
    GRANULES_32,

    SMALL_OBJECT_CHUNK_KINDS,
    FREE_LARGE_OBJECT = 254,
    LARGE_OBJECT = 255
}

static const uint8_t[] small_object_granule_sizes = SMALL_OBJECT_GRANULES;


chunk_kind granules_to_chunk_kind(uint granules)
{
    static foreach(granule; SMALL_OBJECT_GRANULES)
    {
        if(granules <= granule)
            return __traits(getMember, chunk_kind, "GRANULES_"~granule.stringof);

    }
  return chunk_kind.LARGE_OBJECT;
}

static uint chunk_kind_to_granules(chunk_kind kind)
{
  switch (kind) with(chunk_kind)
  {
    static foreach(i, mem; __traits(allMembers, chunk_kind))
    {
        case mixin(mem): return SMALL_OBJECT_GRANULES[i];
    }
    default: return -1;
  }
}

// Given a pointer P returned by malloc(), we get a header pointer via
// P&~PAGE_MASK, and a chunk index via (P&PAGE_MASK)/CHUNKS_PER_PAGE.  If
// chunk_kinds[chunk_idx] is [FREE_]LARGE_OBJECT, then the pointer is a large
// object, otherwise the kind indicates the size in granules of the objects in
// the chunk.
struct page_header {
  uint8_t[CHUNKS_PER_PAGE] chunk_kinds;
}

struct page {
  union {
    page_header header;
    chunk[CHUNKS_PER_PAGE] chunks;
  }
}

enum PAGE_HEADER_SIZE = page_header.sizeof;
enum FIRST_ALLOCATABLE_CHUNK = 1;
static assert(PAGE_HEADER_SIZE == FIRST_ALLOCATABLE_CHUNK * CHUNK_SIZE);

private page* get_page(void *ptr) {
  return cast(page*) cast(char*) ((cast(size_t) ptr) & ~PAGE_MASK);
}
private uint get_chunk_index(void *ptr)
{
  return ((cast(size_t) ptr) & PAGE_MASK) / CHUNK_SIZE;
}

struct freelist {
  freelist* next;
}

struct large_object {
  large_object* next;
  size_t size;
}

enum LARGE_OBJECT_HEADER_SIZE = large_object.sizeof;

private pragma(inline, true) void* get_large_object_payload(large_object *obj) {
  return (cast(char*) obj) + LARGE_OBJECT_HEADER_SIZE;
}
private pragma(inline, true) large_object* get_large_object(void *ptr) {
  return cast(large_object*) ((cast(char*) ptr) - LARGE_OBJECT_HEADER_SIZE);
}

pragma(LDC_intrinsic, "llvm.wasm.memory.grow.i32")
@trusted pure nothrow private int llvm_wasm_memory_grow(int mem, int delta);


// in 64 KB pages
pragma(LDC_intrinsic, "llvm.wasm.memory.size.i32")
@trusted pure nothrow private int llvm_wasm_memory_size(int mem);

private freelist*[chunk_kind.SMALL_OBJECT_CHUNK_KINDS] small_object_freelists;
private large_object* large_objects;

private extern extern(C) ubyte __heap_base;
private __gshared size_t walloc_heap_size;


nothrow @nogc @trusted size_t getWallocHeapSize()
{
  return walloc_heap_size;
}

private page* allocate_pages(size_t payload_size, size_t *n_allocated)
{
  size_t needed = payload_size + PAGE_HEADER_SIZE;
  size_t heap_size = llvm_wasm_memory_size(0) * PAGE_SIZE;
  uintptr_t base = cast(uintptr_t)heap_size;
  uintptr_t preallocated = null, grow = null;

  if (!walloc_heap_size) {
    // We are allocating the initial pages, if any.  We skip the first 64 kB,
    // then take any additional space up to the memory size.
    uintptr_t heap_base = align_(cast(uintptr_t)&__heap_base, cast(uintptr_t)PAGE_SIZE);
    preallocated = cast(uintptr_t)(heap_size - cast(size_t)heap_base); // Preallocated pages.
    walloc_heap_size = cast(size_t)preallocated;
    base-= cast(size_t)preallocated;
  }

  if (cast(size_t)preallocated < needed) {
    // Always grow the walloc heap at least by 50%.
    grow = align_(cast(uintptr_t)max(walloc_heap_size / 2, needed - cast(size_t)preallocated),
                 cast(uintptr_t)PAGE_SIZE);
    assert(grow);
    if (llvm_wasm_memory_grow(0, (cast(int)grow) >> PAGE_SIZE_LOG_2) == -1) {
      return null;
    }
    walloc_heap_size += cast(size_t)grow;
  }

  page *ret = cast(page *)base;
  size_t size = cast(size_t)grow + cast(size_t)preallocated;
  assert(size);
  assert_aligned(cast(uintptr_t)size, PAGE_SIZE);
  *n_allocated = size / PAGE_SIZE;
  return ret;
}

char* allocate_chunk(page *page, uint idx, chunk_kind kind)
{
  page.header.chunk_kinds[idx] = cast(ubyte)kind;
  return page.chunks[idx].data.ptr;
}

// It's possible for splitting to produce a large object of size 248 (256 minus
// the header size) -- i.e. spanning a single chunk.  In that case, push the
// chunk back on the GRANULES_32 small object freelist.
private void maybe_repurpose_single_chunk_large_objects_head()
{
  if (large_objects.size < CHUNK_SIZE) {
    uint idx = get_chunk_index(large_objects);
    char *ptr = allocate_chunk(get_page(large_objects), idx, chunk_kind.GRANULES_32);
    large_objects = large_objects.next;
    freelist* head = cast(freelist *)ptr;
    head.next = small_object_freelists[chunk_kind.GRANULES_32];
    small_object_freelists[chunk_kind.GRANULES_32] = head;
  }
}

// If there have been any large-object frees since the last large object
// allocation, go through the freelist and merge any adjacent objects.
private int pending_large_object_compact = 0;
private large_object** maybe_merge_free_large_object(large_object** prev)
{
  large_object *obj = *prev;
  while (1) {
    char *end = cast(char*)(get_large_object_payload(obj) + obj.size);
    assert_aligned(cast(uintptr_t)end, CHUNK_SIZE);
    uint chunk = get_chunk_index(end);
    if (chunk < FIRST_ALLOCATABLE_CHUNK) {
      // Merging can't create a large object that newly spans the header chunk.
      // This check also catches the end-of-heap case.
      return prev;
    }
    page *page = get_page(end);
    if (page.header.chunk_kinds[chunk] != chunk_kind.FREE_LARGE_OBJECT) {
      return prev;
    }
    large_object *next = cast(large_object*) end;

    large_object **prev_prev = &large_objects;
    large_object* walk = large_objects;
    while (1) {
      assert(walk);
      if (walk == next) {
        obj.size += LARGE_OBJECT_HEADER_SIZE + walk.size;
        *prev_prev = walk.next;
        if (prev == &walk.next) {
          prev = prev_prev;
        }
        break;
      }
      prev_prev = &walk.next;
      walk = walk.next;
    }
  }
}
private void maybe_compact_free_large_objects()
{
  if (pending_large_object_compact) {
    pending_large_object_compact = 0;
    large_object **prev = &large_objects;
    while (*prev) {
      prev = &(*maybe_merge_free_large_object(prev)).next;
    }
  }
}

// Allocate a large object with enough space for SIZE payload bytes.  Returns a
// large object with a header, aligned on a chunk boundary, whose payload size
// may be larger than SIZE, and whose total size (header included) is
// chunk-aligned.  Either a suitable allocation is found in the large object
// freelist, or we ask the OS for some more pages and treat those pages as a
// large object.  If the allocation fits in that large object and there's more
// than an aligned chunk's worth of data free at the end, the large object is
// split.
//
// The return value's corresponding chunk in the page as starting a large
// object.
private large_object* allocate_large_object(size_t size) {
  maybe_compact_free_large_objects();
  large_object *best = null;
  large_object **best_prev = &large_objects;
  size_t best_size = -1;

  large_object** prev = &large_objects;
  large_object* walk = large_objects;
  for (;
       walk;
       prev = &walk.next, walk = walk.next) {
    if (walk.size >= size && walk.size < best_size) {
      best_size = walk.size;
      best = walk;
      best_prev = prev;
      if (cast(uintptr_t)(best_size + LARGE_OBJECT_HEADER_SIZE)
          == align_(cast(uintptr_t)(size + LARGE_OBJECT_HEADER_SIZE), cast(uintptr_t)CHUNK_SIZE))
        // Not going to do any better than this; just return it.
        break;
    }
  }

  if (!best) {
    // The large object freelist doesn't have an object big enough for this
    // allocation.  Allocate one or more pages from the OS, and treat that new
    // sequence of pages as a fresh large object.  It will be split if
    // necessary.
    size_t size_with_header = size + large_object.sizeof;
    size_t n_allocated = 0;
    page *page = allocate_pages(size_with_header, &n_allocated);
    if (!page) {
      return null;
    }
    char *ptr = allocate_chunk(page, FIRST_ALLOCATABLE_CHUNK, chunk_kind.LARGE_OBJECT);
    best = cast(large_object *)ptr;
    size_t page_header = ptr - (cast(char*) page);
    best.next = large_objects;
    best.size = best_size =
      n_allocated * PAGE_SIZE - page_header - LARGE_OBJECT_HEADER_SIZE;
    assert(best_size >= size_with_header);
  }

  allocate_chunk(get_page(best), get_chunk_index(best), chunk_kind.LARGE_OBJECT);

  large_object *next = best.next;
  *best_prev = next;

  size_t tail_size = (best_size - size) & ~CHUNK_MASK;
  if (tail_size) {
    // The best-fitting object has 1 or more aligned chunks free after the
    // requested allocation; split the tail off into a fresh aligned object.
    page *start_page = get_page(best);
    char *start = cast(char*)get_large_object_payload(best);
    char *end = start + best_size;

    if (start_page == get_page(end - tail_size - 1)) {
      // The allocation does not span a page boundary; yay.
      assert_aligned(cast(uintptr_t)end, CHUNK_SIZE);
    } else if (size < PAGE_SIZE - LARGE_OBJECT_HEADER_SIZE - CHUNK_SIZE) {
      // If the allocation itself smaller than a page, split off the head, then
      // fall through to maybe split the tail.
      assert_aligned(cast(uintptr_t)end, PAGE_SIZE);
      size_t first_page_size = PAGE_SIZE - ((cast(size_t)cast(uintptr_t)start) & PAGE_MASK);
      large_object *head = best;
      allocate_chunk(start_page, get_chunk_index(start), chunk_kind.FREE_LARGE_OBJECT);
      head.size = first_page_size;
      head.next = large_objects;
      large_objects = head;

      maybe_repurpose_single_chunk_large_objects_head();

      page *next_page = start_page + 1;
      char *ptr = allocate_chunk(next_page, FIRST_ALLOCATABLE_CHUNK, chunk_kind.LARGE_OBJECT);
      best = cast(large_object *) ptr;
      best.size = best_size = best_size - first_page_size - CHUNK_SIZE - LARGE_OBJECT_HEADER_SIZE;
      assert(best_size >= size);
      start = cast(char*)get_large_object_payload(best);
      tail_size = (best_size - size) & ~CHUNK_MASK;
    } else {
      // A large object that spans more than one page will consume all of its
      // tail pages.  Therefore if the split traverses a page boundary, round up
      // to page size.
      assert_aligned(cast(uintptr_t)end, PAGE_SIZE);
      size_t first_page_size = PAGE_SIZE - ((cast(size_t)cast(uintptr_t)start) & PAGE_MASK);
      size_t tail_pages_size = cast(size_t)align_(cast(uintptr_t)(size - first_page_size), cast(uintptr_t)PAGE_SIZE);
      size = first_page_size + tail_pages_size;
      tail_size = best_size - size;
    }
    best.size -= tail_size;

    uint tail_idx = get_chunk_index(end - tail_size);
    while (tail_idx < FIRST_ALLOCATABLE_CHUNK && tail_size) {
      // We would be splitting in a page header; don't do that.
      tail_size -= CHUNK_SIZE;
      tail_idx++;
    }

    if (tail_size) {
      page *page = get_page(end - tail_size);
      char *tail_ptr = allocate_chunk(page, tail_idx, chunk_kind.FREE_LARGE_OBJECT);
      large_object *tail = cast(large_object *) tail_ptr;
      tail.next = large_objects;
      tail.size = tail_size - LARGE_OBJECT_HEADER_SIZE;
      assert_aligned(cast(uintptr_t)(get_large_object_payload(tail) + tail.size), CHUNK_SIZE);
      large_objects = tail;

      maybe_repurpose_single_chunk_large_objects_head();
    }
  }

  assert_aligned(cast(uintptr_t)(get_large_object_payload(best) + best.size), CHUNK_SIZE);
  return best;
}

private freelist*
obtain_small_objects(chunk_kind kind) {
  freelist** whole_chunk_freelist = &small_object_freelists[chunk_kind.GRANULES_32];
  void *chunk;
  if (*whole_chunk_freelist) {
    chunk = *whole_chunk_freelist;
    *whole_chunk_freelist = (*whole_chunk_freelist).next;
  } else {
    chunk = allocate_large_object(0);
    if (!chunk) {
      return null;
    }
  }
  char *ptr = allocate_chunk(get_page(chunk), get_chunk_index(chunk), kind);
  char *end = ptr + CHUNK_SIZE;
  freelist *next = null;
  size_t size = chunk_kind_to_granules(kind) * GRANULE_SIZE;
  for (size_t i = size; i <= CHUNK_SIZE; i += size) {
    freelist *head = cast(freelist*) (end - i);
    head.next = next;
    next = head;
  }
  return next;
}

private pragma(inline, true) size_t size_to_granules(size_t size) {
  return (size + GRANULE_SIZE - 1) >> GRANULE_SIZE_LOG_2;
}
private freelist** get_small_object_freelist(chunk_kind kind) {
  assert(kind < chunk_kind.SMALL_OBJECT_CHUNK_KINDS);
  return &small_object_freelists[kind];
}

private void* allocate_small(chunk_kind kind)
{
  freelist **loc = get_small_object_freelist(kind);
  if (!*loc) {
    freelist *freelist = obtain_small_objects(kind);
    if (!freelist) {
      return null;
    }
    *loc = freelist;
  }
  freelist *ret = *loc;
  *loc = ret.next;
  return cast(void *) ret;
}

private void* allocate_large(size_t size) {
  large_object *obj = allocate_large_object(size);
  return obj ? get_large_object_payload(obj) : null;
}

export void* malloc(size_t size) @nogc @trusted nothrow
{
  size_t granules = size_to_granules(size);
  chunk_kind kind = granules_to_chunk_kind(granules);
  return (kind == chunk_kind.LARGE_OBJECT) ? allocate_large(size) : allocate_small(kind);
}

export void free(void *ptr) @nogc @trusted nothrow
{
  if (!ptr) return;
  page *page = get_page(ptr);
  uint chunk = get_chunk_index(ptr);
  uint8_t kind = page.header.chunk_kinds[chunk];
  if (kind == chunk_kind.LARGE_OBJECT) {
    large_object *obj = get_large_object(ptr);
    obj.next = large_objects;
    large_objects = obj;
    allocate_chunk(page, chunk, chunk_kind.FREE_LARGE_OBJECT);
    pending_large_object_compact = 1;
  } else {
    size_t granules = kind;
    freelist **loc = get_small_object_freelist(cast(chunk_kind)granules);
    freelist *obj = cast(freelist*)ptr;
    obj.next = *loc;
    *loc = obj;
  }
}

export
void* realloc(void* ptr, size_t newSize) @nogc nothrow @system {
    if (!ptr)
        return malloc(newSize);

    size_t oldSize = get_alloc_size(ptr);
    if (oldSize >= newSize)
        return ptr;

    // Size is bigger, realloc just to be sure.
    void* n_mem = malloc(newSize);
    if(oldSize != 0)
    {
        llvm_memmove(n_mem, ptr, oldSize, false);
        free(ptr);
    }
    return n_mem;
}


size_t get_alloc_size(void* ptr) {
    page* page = get_page(ptr);
    size_t chunk = get_chunk_index(ptr);
    ubyte kind = page.header.chunk_kinds[chunk];

    if (kind == chunk_kind.LARGE_OBJECT) {
        large_object* obj = get_large_object(ptr);
        return obj.size;
    }


    switch(kind) with (chunk_kind)
    {
        case GRANULES_1: return 1 * GRANULE_SIZE;
        case GRANULES_2: return 2 * GRANULE_SIZE;
        case GRANULES_3: return 3 * GRANULE_SIZE;
        case GRANULES_4: return 4 * GRANULE_SIZE;
        case GRANULES_5: return 5 * GRANULE_SIZE;
        case GRANULES_6: return 6 * GRANULE_SIZE;
        case GRANULES_8: return 8 * GRANULE_SIZE;
        case GRANULES_10: return 10 * GRANULE_SIZE;
        case GRANULES_16: return 16 * GRANULE_SIZE;
        case GRANULES_32: return 32 * GRANULE_SIZE;
        default:
        {
            import std.stdio;
            writeln("Reurning kind ", kind);
            return kind;
        }
    }
}