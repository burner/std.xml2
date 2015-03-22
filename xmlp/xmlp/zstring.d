/**
Whats this?  A custom Array struct type, with reference counting, in a D2 module!
What a crackpot idea. But its an idea.

Copyright: Copyright Michael Rynn 2012.
Authors: Michael Rynn
License: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.

Advantages ?
Fun of debugging. It does copy on write, if reference count is > 1. 
Relies on D struct PostBlit and Destructor, to manage reference count. This seems to work well.

All allocations include an extra T.sizeof space after the indicated capacity.

---
static if (isSomeChar!T) {
	void nullTerminate()
---

The nullTerminate function is easy, causes no memory allocation, as there is always 1 extra space,
, its also an exception to the copyOnWrite principle for character arrays.  Appending or shrinking will
lose the nullTerminate, so it would be called every time before an OS api, by using the cstr  property.

Easy to put inside other struct or classes. On stack or clases, is less likely to be blitted around.
Destructor leaves memory destruction to the GC, as no there seems no way to tell if it was the GC that called finalizer.
Errors are sure to occur during attempts to free data from the destructor during garbage collection.
Other working methods may result in calls to free, such as with dynamic resizing, appending and writes.
Internal resizing moves and copies raw memory. 
Keeping a reference to the internal pointer outside of the array is unsafe. Calling the writeable pointer property ptr(), will trigger
a copyOnWrite if reference count is not 1.

Memory destruction could be turned on for None garbage collecting memory management environment, if anyone actually dared.

Disadvantages.
Extra code generated with templates for each type.
Extra overhead to check reference count, and for post-blit and destructor check.
Extra memory prefix overhead of (uintptr_t * 2). An extra T.sizeof is kept for character types for nullTerminate().

Memory model:
prefix{capacity, refcount} ptr {0 .. length * T.sizeof [ (capacity-length) * T.sizeof ] [<char> T.sizeof ]} 
The length property is kept local. Modifying it will trigger copyOnWrite.

--- 
//version=NoGarbageCollection;
---
*/

module alt.zstring;

import std.utf;
import std.string;
import std.stdio;
import std.stream;
import std.stdint;
import std.traits;
import std.c.string;
import std.conv;
import std.variant;

private import core.memory;


class AltStringError : Exception
{
    this(string s)
    {
        super(s);
    }
}



version(NoGarbageCollection)
{
	private enum DoDeletes = true;
}
else {
	private enum DoDeletes = false;
}

private {
	private struct ArrayPrefix {
		uintptr_t   capacity_;
		intptr_t	refcount_;
	}

	version(NoGarbageCollection)
		static intptr_t allocCount, blockCount;

	void freeCapacity(ArrayPrefix* pap)
	{
		if (pap is null)
			return;
		version(NoGarbageCollection)
		{
			allocCount -= pap.capacity_;
			blockCount -= 1;
		}
		GC.free(pap);
	}
	void destroy_data(T)(T* dest, size_t nlen)
	{
		T* end = dest + nlen;
		while(dest < end)
		{
			static if (hasElaborateDestructor!(T))
				typeid(T).destroy(dest);
			else
				*dest = T.init;
			dest++;
		}

	}
	void copy_create(T)(T* dest, const(T)* src, size_t nlen)
	{
		T* end = dest + nlen;
		while(dest < end)
		{
			*dest = * cast(T*) (cast(void*) src);
			dest++;
			src++;
		}
		//new (dest) T(*src);
	}
	/// structs never have a argumentless constructor
	void init_create(T)(T* dest, size_t nlen)
	{
		T* end = dest + nlen;
		while(dest < end)
		{
			*dest = T.init;
			dest++;
		}
	}


	ArrayPrefix* createCapacity(T)(uintptr_t cap, GC.BlkAttr flags = cast(GC.BlkAttr)0)
	{
		// No point in being APPENDABLE if always making a new block.
		static if (isSomeChar!T)
		{
			uintptr_t allocSize = cap*T.sizeof + ArrayPrefix.sizeof + T.sizeof; // zero termination always possible.
			auto info = GC.qalloc(allocSize, GC.BlkAttr.NO_SCAN | flags);
		}
		else {
			uintptr_t allocSize = cap*T.sizeof + ArrayPrefix.sizeof;
			auto info = GC.qalloc(allocSize, (typeid(T[]).next.flags & 1) ? 0 : GC.BlkAttr.NO_SCAN | flags);
		}
		memset(info.base,0,info.size);
		auto newCap = (info.size - ArrayPrefix.sizeof) / T.sizeof;
		static if (isSomeChar!T)
		{
			newCap--;
		}
		ArrayPrefix* pap = cast(ArrayPrefix*) info.base;
		version(NoGarbageCollection)
		{
			allocCount += newCap;
			blockCount += 1;
		}
		pap.refcount_ = 1;
		pap.capacity_ = newCap;
		
		return pap;
	}
}
version(NoGarbageCollection)
{
void getStats(ref intptr_t albytes, ref intptr_t alblocks)
{
	albytes = allocCount;
	alblocks = blockCount;
}
}
/** Always gets a new block. Array length preserved. Capacity request adjusted to be at least current length */

class AltIndexException : Exception
{
    this(string s)
    {
        super(s);
    }
    static void throwIndexError(uintptr_t ix)
    {
        throw new AltIndexException(text(ix , " exceeds length"));
    }
    static void throwSliceError(uintptr_t p1, uintptr_t p2)
    {
        throw new AltIndexException(text("Slice error: ", p1, " to ", p2));
    }
};

import core.memory;

private {
enum alignBits = uintptr_t.sizeof;
enum alignMask = alignBits - 1;
enum alignData = ~alignMask;
}

T getNextPower2(T)(T k) {
	if (k == 0)
		return 1;
	k--;
	for (int i=1; i < (T.sizeof * 8); i<<=1)
		k = k | (k >> i);
	return k+1;
}

unittest {
	/*
	assert(getNextPower2(1)==2);
	assert(getNextPower2(2)==2);
	assert(getNextPower2(3)==4);
	assert(getNextPower2(1023)==1024);
	*/
}
struct Array(T)
{
    private
    {
        T*           ptr_;
        uintptr_t    length_;

		alias Array!T			SameTypeArray;
		alias immutable(T)[]    IMArray;
		alias const(T)[]		CNArray;
    }

	/// Post-Blit - Now I really am in trouble. 
	this(this)
	{
		if (ptr_)
		{
			ArrayPrefix* pap = cast(ArrayPrefix*)ptr_ - 1;
			if (pap.refcount_ > 0)
				pap.refcount_++;
		}
	}

	bool opCast(bool)
	{
		return (ptr_ !is null);
	}
	~this()
	{
		deallocate(DoDeletes);
	}

	/// Change GC behaviour on this array. Required by having  NO_INTERIOR for linked AA buckets
	/// Bug : GC will garbage collect pointer if the NO_INTERIOR flag is set after initial allocation.
	void initNoInterior(uintptr_t len)
	{
		if (ptr_)
		{
			deallocate(DoDeletes);
		}
		ArrayPrefix* npap =  createCapacity!T(len, GC.BlkAttr.NO_INTERIOR);
		ptr_ = cast(T*) (npap+1);
		length_ = len;

	}
	/// define as within capacity or within length?
	bool isInside(const(T)* p) const
	{
		if (!ptr_)
			return false;
		else
		{
			ArrayPrefix* pap = cast(ArrayPrefix*)ptr_ - 1;
			return ((p >= ptr_) && (p < (ptr_ + pap.capacity_ )));
		}
	}
	void append( const(T)* buf, uintptr_t slen)
	{
		if (slen == 0)
			return;
		SameTypeArray copy;
		if (isInside(buf))
			copy = this;
		auto origlen = length_;
		alterLength(origlen + slen);
		copy_create!T(ptr_ + origlen, buf, slen);
	}	
	private void deallocate(bool del=false)
	{
		if (ptr_)
		{
			auto pap = cast(ArrayPrefix*)(ptr_) - 1;
			if (pap.refcount_ > 0)
			{
				pap.refcount_--;
				if (!pap.refcount_)
				{
					destroy_data!T(ptr_, length_);
					if (del)
					{
						freeCapacity(pap);
					}
				}
			}
			ptr_ = null;
			length_ = 0;
		}
	}


	uintptr_t capacity()  const @property
	{
		if (!ptr_)
			return 0;
		auto pap = cast(ArrayPrefix*)(ptr_) - 1;
		return pap.capacity_;
	}
	
	private final void copyOnWrite()
	{
		if (ptr_ is null)
			return;
		if (((cast(ArrayPrefix*)ptr_)-1).refcount_ != 1)
			assign(ptr_,length_);
	}	

	private void alterLength(uintptr_t nlen)
	{
		if (ptr_)
		{
			immutable oldlen = length_;
			ArrayPrefix* pap = cast(ArrayPrefix*)ptr_-1;
			if (pap.refcount_ == 1) // safe to quickly change
			{
				if (nlen < oldlen)
				{
					length_ = nlen; 
					return;
				}
				// special case
				if (nlen <= pap.capacity_)
				{
					length_ = nlen; 
					return;
				}
			}
		}
		// empty or not only copys
		reserve(nlen);
		length_ = nlen;
	}
	
	void setAll(T value)
	{
		copyOnWrite();
		T* dest = ptr_;
		T* end = ptr_ + length_;
		while (dest < end)
		{
			*dest = value;
			dest++;
		}
	}
	void length(uintptr_t x) @property
	{
		if (ptr_)
		{
			size_t oldlen = length_;
			if (oldlen == x)
				return;
			auto pap = cast(ArrayPrefix*)ptr_-1;
			immutable notShared = (pap.refcount_ == 1);
			if (notShared)
			{
				if (oldlen > x)
				{
					destroy_data!T(ptr_+x, oldlen - x);
					length_ = x;
				}
				else {
					auto scap = pap.capacity_;
					if (x > scap)
					{
						reserve(x); // ptr_ expected to change
						pap = cast(ArrayPrefix*)ptr_-1;
					}
					length_ = x;
					init_create(ptr_ + oldlen, x - oldlen);
				}
			}
			else {
				reserve(x);
				// reserve will have made this a new copy, doing a create_copy  minimum length of (x, oldlen)
				// the valid length will be minimum of (x, oldlen)
				length_ = x;
				if (oldlen < x)
				{
					init_create(ptr_ + oldlen, x - oldlen);
				}
			}
			return;
		}
		reserve(x);
		length_ = x;
		init_create(ptr_,x);
	}

	void capacity(uintptr_t len) @property
	{
		reserve(len, true);
	}
	/// ensures capacity. duplicate if changing a shared or immutable array
	void reserve (uintptr_t len, bool exactLen = false)
	{
		if (ptr_)
		{
			if (!exactLen)
			{
				len = getNextPower2(len);
			}
			auto pap = cast(ArrayPrefix*)ptr_-1;
			auto oldcap =  pap.capacity_;
			immutable isShared = ((pap.refcount_ > 1) || (pap.refcount_ < 0));

			if ( isShared || (len > oldcap) )
			{
				ArrayPrefix* npap = createCapacity!T(len);
				auto dataptr = cast(T*)(npap+1);
				if (length_ > 0) //prior set length to 0 if doing assign
				{
					auto len_copy = length_;
					if (len_copy > len) 
						len_copy = len; // This might make the copied segment shorter. Why?
					if (isShared)
						copy_create(dataptr, ptr_, len_copy);
					else 
						memcpy(dataptr, ptr_, len_copy*T.sizeof);
					length_ = len_copy;
				}
				if (isShared)
				{
					if (pap.refcount_ > 0)
						pap.refcount_--; // it was at least 2
				}
				else {
					//Allocator::free(h);
					freeCapacity(pap);
				}
				ptr_ = dataptr;
			}
		}
		else {
			ArrayPrefix* npap =  createCapacity!T(len);
			ptr_ = cast(T*) (npap+1);
		}
	}
	// also does copyOnWrite
	void assign(const(T)* buf, size_t slen)
	{
		if (slen == 0)
		{
			length(0);
			return;   
		}
		SameTypeArray copy;
		if (ptr_)
			copy = this;
		reserve(slen, true);
		copy_create!T(ptr_, buf, slen);
		length_ = slen;
	}
	void opAssign(immutable(T)[] s)
	{
		assign(s.ptr, s.length);
	}
	void opAssign(const(T)[] s)
	{
		assign(s.ptr, s.length);
	}

	this(const(T)[] s)
	{
		opAssign(s);
	}

	static if (isSomeChar!T)
	{
		int opApply(int delegate(dchar value) dg)
		{
			// let existing D code do it.
			if (ptr_ is null)
				return 0;
			auto slice = ptr_[0..length_];
			uintptr_t ix = 0;
			while (ix < slice.length)
			{
				dchar d = decode(slice,ix);
				auto result = dg(d);
				if (result)
					return result;
			}
			return 0;
		}

		/// Always allowed to append 0 at index of length_, 
		void nullTerminate() 
		{
			if (!ptr_)
			{
				// At least no one else owns this!
				length(0);
			}
			// always a space at the back
			ptr_[length_] = 0;
		}

		const(T)* cstr() @property
		{
			nullTerminate();
			return constPtr();
		}
	}

	T opIndex(uintptr_t ix)
	{
		version(BoundsChecking)
		{
			if (ptr_ is null || ix >= length_)
			{
				throw AltIndexException.getIndexError(ix);
			}
		}
		return ptr_[ix];
	}
	void opCatAssign(const(T)[] data)
	{
		append(data.ptr, data.length);
	}

	/// TODO: opSlice
    /// Return readonly slice of internal buffer.
    const(T)[] slice(uintptr_t p1, uintptr_t p2)
    {
        if (p1 > p2 || p2 > length_)
            AltIndexException.throwSliceError(p1,p2);
        return ptr_[p1..p2];
    }

    /// Replace a value in the buffer
    void opIndexAssign(T value, uintptr_t ix)
    {
		version(BoundsChecking)
		{
			if (ptr_ is null || ix >= length_)
			{
				throw AltIndexException.getIndexError(ix);
			}
		}
		copyOnWrite();
        ptr_[ix] = value;
    }

    /// Append single T
    void opCatAssign(T value)
    {
        put(value);
    }

	/// remove any items equal to T.init, starting from pos;
	void pack(uintptr_t	pos = 0)
	{
		if (!ptr_ || length_ == 0)
			return;
		copyOnWrite();
		T* ok = ptr_ + pos;
		T* end = ptr_ + length_;
		while ( (ok < end) && (*ok !is T.init) )
			ok++;
		T* adv = ok + 1;
		while (adv < end)
		{
			if (*adv !is T.init)
			{
				*ok++ = *adv++;
			}
			else
				adv++;
		}
		length_ = (ok - ptr_);
	}
    /// Equivalent to X.length = 0, retains buffer and capacity with wipe if necessary
    final void clear()
    {
		if (!ptr_)
			return;
		copyOnWrite();
		if (length_ > 0)
			destroy_data!T(ptr_,length_);
        length_ = 0;
	}
    /// Take away internal buffer as if is its single immutable reference. This may change
	static if (isSomeChar!T)
	{
		@property IMArray unique()
		{
			if (!ptr_)
				return null;
			if (((cast(ArrayPrefix*)ptr_)-1).refcount_ == 1)
			{
				auto result = (cast(immutable(T)*)ptr_)[0..length_];
				ptr_ = null;
				length_ = 0;
				return result;
			}
			auto result = ptr_[0..length_].idup;
			deallocate(true);
			return result;
		}
	}
    /// Return the internal buffer as writable array. This may change
    @property T[] take()
    {
		if (!ptr_)
			return null;
		if (((cast(ArrayPrefix*)ptr_)-1).refcount_ == 1)
		{
			auto result = ptr_[0..length_];
			ptr_ = null;
			length_ = 0;
			return result;
		}
		auto result = ptr_[0..length_].dup;
		deallocate(true);
        return result;
    }

    /// Return index of single T, or -1
	static if (!is(T==Variant))
	{
    final intptr_t indexOf(T value) const
    {
        for(auto ix = 0; ix < length_; ix++)
        {

			if (ptr_[ix] == value)
				return ix;
        }
        return -1;
    }
	}
    /**
        Forget the buffer data, may leave to GC
    */
    final void forget()
    {
		deallocate();
    }
    /**
	Free the buffer data if refcount == 1. Must not call from a Destructor with true
    */
    final void free(bool del = false)
    {
		deallocate(del);
    }	

    /**
	free the buffer data
    */
    /// Return  writeable slice of the buffer.
    T[] toArray() @property 
    {
		if (!ptr_)
			return [];
		copyOnWrite();
		return  ptr_[0..length_];
    }

    /// Return  unwriteable slice of the buffer.
    const(T[]) toConstArray() const @property nothrow
    {
		if (ptr_ !is null)
			return ptr_[0..length_];
		else
			return [];
    }

    /// append T[]
    void put(const(T)[] str)
    {
		if (str.length > 0)
			append(str.ptr, str.length);
    }
	
	/// append array of same type
	void put(ref Array!T c)
	{
		put(c.toConstArray());
	}

    /// Get pointer to internal buffer
    @property const(T)* constPtr() const
    {
        return ptr_;
    }

    /// Get pointer to internal buffer. Ensures reference count is 1, triggers copyOnWrite if it is not.
    @property T* ptr()
    {
		if (!ptr_)
			return null;
		copyOnWrite();
        return ptr_;
    }

    /// Get pointer to last value of internal buffer
    @property T* last()
    {
        if (length_ == 0)
            throw new AltIndexException("last: empty array");
		copyOnWrite();
        return &ptr_[length_-1];
    }

    /// Empty if length is zero
    bool empty()  @property 
    {
        return (length_ == 0);
    }
	/// sort is supposed to be in place
	const(T)[] sort() @property 
	{
		if(length_ <= 1)
			return (ptr_)[0..length_];
		copyOnWrite();
		auto temp = (ptr_)[0..length_];
		if (length_ > 1)
		{
			temp = temp.sort;
		}
		return temp;
	}


    T front()
    {
        if (length_ == 0)
            throw new AltIndexException("last: empty array");
        return ptr_[0];
    }
    ///
    T back()
    {
        if (length_ == 0)
            throw new AltIndexException("back: empty array");
        return ptr_[length_-1];
    }
    /// popFront not supported
    void popBack()
    {
        if (length_ == 0)
            throw new AltIndexException("popBack on empty buffer");
		copyOnWrite();
        length_--;
        ptr_[length_] = T.init;
    }

    alias put push;

    /// simple append T to buffer
	private void roomForExtra(uintptr_t extra)
	{
		if (ptr_ is null)
		{
			reserve(extra);
		}
		else {
			auto pap = (cast(ArrayPrefix*)ptr_)-1;
			if ( pap.refcount_ != 1 || (length_ + extra > pap.capacity_) )
				reserve(length_ + extra);
		}
	}

    void put(T c)
    {
		roomForExtra(1);
        ptr_[length_] = c;
		length_++;
    }
	void put(T* pt)
	{
		roomForExtra(1);
        ptr_[length_] = *pt;
		length_++;
	}
	bool opEquals(ref const SameTypeArray ro) const
	{
		auto lhs = this.toConstArray();
		auto rhs = ro.toConstArray();

		return typeid(T[]).equals(&rhs, &lhs);
	}
	intptr_t opCmp(ref const SameTypeArray ro) const
	{

		auto lhs = this.toConstArray();
		auto rhs = ro.toConstArray();

		return typeid(T[]).compare(&lhs, &rhs);

	}

    static if (isSomeChar!(T))
    {
        @property immutable(T)[] idup()
        {
			if (ptr_ is null)
				return null;
            return (cast(T*)ptr_)[0..length_].idup;
        }

        static if(!is(T == dchar))
        {
            /// encode append dchar to buffer as UTF Ts
            void put(dchar c)
            {
                static if (is(T==char))
                {
                    if (c < 0x80)
                    {
                        roomForExtra(1);
                        ptr_[length_++] = cast(char)c;
                        return;
                    }
                    T[4] encoded;
					if (c == 163)
					{
						c = 163;
					}
                    auto len = std.utf.encode(encoded, c);
					roomForExtra(len);
                    auto cptr = ptr_ + length_;
					length_ += len;
                    auto eptr = encoded.ptr;
                    while(len > 0)
                    {
						len--;
                        *cptr++ = *eptr++;
                    }

                }
                else static if (is(T==wchar))
                {
                    if (c < 0xD800)
                    {
						roomForExtra(1);
                        ptr_[length_++] = cast(wchar)c;
                        return;
                    }
                    else
                    {
                        T[2] encoded;
                        auto len = std.utf.encode(encoded, c);
						roomForExtra(len);
                        auto wptr = ptr_ + length_;
						length_ += len;
                        auto eptr = encoded.ptr;
                        while(len > 0)
                        {
							len--;
                            *wptr++ = *eptr++;
                        }

                    }
                }
            }
        }

        void opCatAssign(dchar c)
        {
            put(c);
        }
    }

    static  if (is(T==char))
    {
        /// OpAssigns are opCatAssigns
        void  opAssign(const(wchar)[] s)
        {
			copyOnWrite();
			length_ = 0;
            opCatAssign(s);
        }
        void  opAssign(const(dchar)[] s)
        {
			copyOnWrite();
			length_ = 0;
            opCatAssign(s);
        }

        void opCatAssign(const(wchar)[] s)
        {
            immutable slen = s.length;
			roomForExtra(slen);
            for (uintptr_t i = 0; i < slen;)
            {
                wchar c = s[i];
                if (c > 0x7F)
                {
                    dchar d = decode(s, i);
                    put(d);
                }
                else
                {
                    i++;
					roomForExtra(1);
                    ptr_[length_++] = cast(char) c;
                }
            }
        }

        void opCatAssign(const(dchar)[] s)
        {
            immutable slen = s.length;
			roomForExtra(slen);
            for (uintptr_t i = 0; i < slen; i++)
            {
                dchar d = s[i];
                if (d > 0x7F)
                {
                    put(d);
                }
                else
                {
					roomForExtra(1);
                    ptr_[length_++] = cast(char)d;
                }
            }
        }
    }
    static  if (is(T==wchar))
    {
        /// OpAssigns are opCatAssigns
        void  opAssign(const(dchar)[] s)
        {
			copyOnWrite();
            length_ = 0;
            opCatAssign(s);
        }
        void  opAssign(const(char)[] s)
        {
			copyOnWrite();
            length_ = 0;
            opCatAssign(s);
        }
        void  opCatAssign(const(char)[] s)
        {
            immutable slen = s.length;
			roomForExtra(slen);
            for (size_t i = 0; i < slen; )
            {
                dchar d = s[i];
                if (d > 0x7F)
                {
                    d = decode(s, i);
                    put(d);
                }
                else
                {
                    i++;
					roomForExtra(1);
                    ptr_[length_++] = cast(wchar)d;
                }
            }
        }

        void opCatAssign(const(dchar)[] s)
        {
            immutable slen = s.length;
			roomForExtra(slen);
            for (size_t i = 0; i < slen; i++)
            {
                dchar d = s[i];
                if (d > 0x7F)
                {
                    put(d);
                }
                else
                {
					roomForExtra(1);
                    ptr_[length_++] = cast(wchar)d;
                }
            }
        }
    }
    static  if (is(T==dchar))
    {
        /// OpAssigns are opCatAssigns
        void  opAssign(const(char)[] s)
        {
			copyOnWrite();
            length_ = 0;
            opCatAssign(s);
        }
        void  opAssign(const(wchar)[] s)
        {
			copyOnWrite();
            length_ = 0;
            opCatAssign(s);
        }
        void opCatAssign(const(char)[] s)
        {
            immutable   slen = s.length;
			roomForExtra(slen);
            for (uintptr_t i = 0; i < slen; )
            {
                dchar c = s[i];
                if (c > 0x7F)
                    c = decode(s, i);
                else
                    i++;
                roomForExtra(1);
                ptr_[length_++] = c;
            }
        }
        void opCatAssign(const(wchar)[] s)
        {
            immutable slen = s.length;
			roomForExtra(slen);
            for (uintptr_t i = 0; i < slen;)
            {
                dchar c = s[i];
                if (c > 0x7F)
                    c = decode(s,i);
                else
                    i++;
                roomForExtra(1);
                ptr_[length_++] = c;
            }
        }
    }

    @property T[] dup()
    {
        return (cast(T*)ptr_)[0..length_].dup;
    }

    uintptr_t length() const  @property nothrow @safe 
    {
        return length_;
    }
}

unittest {
	unittest_zstring();
}
void unittest_zstring()
{
    auto cs = "s char";
    auto ws = "s char"w;
    auto ds = "s char"d;

	void testDeallocate()
	{
		Array!char a1;

		a1 = cs;
		a1 = ws;
		a1 = ds;

		struct B {
			Array!char	ba;
		}

		void passB(B b3)
		{
			B b4 = b3;
		}

		void passIt(Array!char c)
		{
			B b1, b2;

			b1.ba = c;
			b2 = b1;
			passB(b1);
		}

		passIt(a1);
	}

	testDeallocate();
    Array!wchar a2;

    a2 = cs;
    a2 = ws;
    a2 = ds;

    Array!dchar a4;

    a4 = cs;
    a4 = ws;
    a4 = ds;

    Array!int ia;

    ia = [1,2,3,4,5,6,7,8];
    for(auto i = 0; i < ia.length; i+=2)
        ia[i] = int.init;
    ia.pack();

    assert(ia.toConstArray == [2,4,6,8]);
}



/**
Allocator purpose is to amortize somewhat the memory and time overhead
of allocating strings which are copied from mutable sources, an alternative to using idup.

This is a trade-off.

Testing showed it used about 70% of memory and about 30% of the time, compared to using idup on char[].
Disadvantage for the Garbage Collector is the resulting strings will behave like slices of one big string.
The whole block will be freed only when all its slices are found not referenced by pointer.
This includes Alloc struct itself, which will be pointing to the last chunk acquired.

This is ideal for where this happens anyway, such that all the strings are part of one document,
or all are temporaries created during processing, such that all are likely to be forgotten at once.

Clients of such documents, in long running applications, should be mindful that retaining a few random pointers
to these allocated strings may incur a bigger memory overhead, if they do not take care to duplicate.

The allocator gets a big chunk from the Garbage Collector, and chops off an aligned block for
each string allocated. The allocator itself cannot track or reclaim allocated strings. When the
remaining block is too small, it is forgotten and replaced by a new chunk.

Savings get less as average string length increases, compared to chunk capacity. Default Chunk is 8192 bytes.


**/


struct ImmuteAlloc(T)
{
private:
    size_t	capacity_ = 0;
    size_t	length_ = 0;
    T*		ptr_ = null;
    size_t	totalAlloc_ = 0; // statistics
public:
    enum { DefaultSliceBlock = 8192};

    this(size_t cap)
    {
        fresh(cap);
    }

    //
    void fresh(size_t cap)
    {
            auto bi = GC.qalloc(cap * T.sizeof,  (typeid(T[]).next.flags & 1) ? 0 : GC.BlkAttr.NO_SCAN);
            ptr_ = cast(T*) bi.base;
            immutable al = bi.size;
            totalAlloc_ += al;
            capacity_ = al / T.sizeof;
            length_ = 0;
    }

    immutable(T)[] alloc(const(T)[] orig)
    {
        immutable slen = orig.length;

        size_t alen = slen;


        if ((alen & alignMask) > 0)
        {
            alen = (alen & alignData) + alignBits;   // zero last 2 bits, add 4
        }
        if (alen + length_ > capacity_)
        {
            if (capacity_ == 0)
                capacity_ = DefaultSliceBlock;

            if (alen > capacity_)
            {
                fresh(alen);
            }
            fresh(capacity_);
        }
        memcpy(ptr_, orig.ptr, slen * T.sizeof);
        immutable(T)[] result = (cast(immutable(T)*)ptr_)[0..slen];
        ptr_ += alen;
        length_ += alen;

        return result;
    }

    @property size_t totalAlloc()
    {
        return totalAlloc_;
    }

}


/** Store a sequence of temporary character strings in a single buffer.
	The string starts are not memory aligned.
	The lengths (end points) are stored as an offset in a seperate buffer to permit random access.
	The indexed values are always still locatable after memory reallocation, whereas storing
	slices of the values array would become invalid.
	Appending and random access by integer index work well.
	Rewrites and removals will not be supported, apart from a
	general reset from scratch. The buffer is intended to be frequently re-used,
	and grows to the maximum size required.

	ends[length1, length1 + length2, length1 + length2 + length3, ...
*/

struct PackedArray(T)
{

    Array!T		     values;
    Array!int        ends;

    @property size_t length() const
    {
        return ends.length;
    }
    void opCatAssign(const (char)[] data)
    {
        auto extent = values.length;
        values.put(data);
        ends.put(cast(int)(data.length+extent));
    }

    // set lengths to zero without sacrificing current buffer capacity.
    void reset()
    {
        values.length = 0;
        ends.length = 0;
    }
    /**
    Retrieve the indexed array as a transient value.

    */

    const(T)[] opIndex(size_t ix)
    {
        auto slen = ends.length;

        if (ix >= slen)
             AltIndexException.throwIndexError(ix);

        auto endLength = ends[ix];
        auto startLength = (ix > 0) ? ends[ix-1] : 0;
        return values.slice(startLength, endLength);
    }
    /**
    	Index match to value
    */
    int indexOf(const(T)[] match)
    {
        auto slen = ends.length;
        if (slen == 0)
            return -1;
        T[] contents = values.toArray;
        auto spos = 0;
        auto epos = 0;
        for(auto i = 0; i < slen; i++)
        {
            epos = ends[i];
            if (match == contents[spos..epos])
                return i;
            epos = spos;
        }
        return -1;
    }
    /** Create array pointing to each individual array.
    	At some point the contents will be overwritten.
    */
    const(T)[][] transient()
    {
        auto slen = ends.length;
        const(T)[][] result = new const(T)[][slen];
        if (slen == 0)
        {
            reset();
            return result;
        }
        T[] contents = values.toArray;
        size_t spos = 0;
        size_t epos = 0;
        for(size_t i = 0; i < slen; i++)
        {
            epos = ends[i];
            result[i] = contents[spos..epos];
            spos = epos;
        }
        return result;
    }
    /** Use a single array to create a whole set of immutable sub-arrays at once.
      The disadvantage will be that for any to be Garbage Collected, all individual arrays
      must be un-referenced. This also resets the original collection
    */
    immutable(T)[][] idup()
    {
        auto slen = ends.length;
        immutable(T)[][] result = new immutable(T)[][slen];
        if (slen == 0)
        {
            return result;
        }
        immutable(T)[] contents = values.idup;
        size_t spos = 0;
        size_t epos = 0;
        for(size_t i = 0; i < slen; i++)
        {
            epos = ends[i];
            result[i] = contents[spos..epos];
            spos = epos;
        }
        reset();
        return result;
    }

    // similar, except use given storage and calfing allocator
    immutable(T)[][] idup(immutable(T)[][] result, ref ImmuteAlloc!(T) strAlloc)
    {
        auto slen = ends.length;
        if (slen == 0)
        {
            reset(); // keep consistant
            return result;
        }
        auto contents = values.toArray;
        size_t spos = 0;
        size_t epos = 0;
        for(size_t i = 0; i < slen; i++)
        {
            epos = ends[i];
            result[i] = strAlloc.alloc(contents[spos..epos]);
            spos = epos;
        }
        reset();
        return result;
    }

}


/// Element of sortable array of pairs on key
struct KeyValRec(K,V)
{
	alias KeyValRec!(K,V) SameType;

    K id;
    V value;

	bool opEquals(ref const SameType ro) const
	{
		return (this.id==ro.id) && (this.value==ro.value);
	}
	const int opCmp(ref const SameType s)
	{
		return typeid(K).compare(&id, &s.id);
	}
}

/** 
	Store pairs of values, possible keyed, in a record array as a struct.

	The AUTOSORT template parameter, adds a binary sort on the key member.
	When using this, to avoid automatic resort with opIndexAssign, either
	call the put method directly, which will flag the need for a sort,
	but just appends to the end, or set the deferSort property, which will have
the same effect in calling opIndexAssign.
	Otherwise, opIndexAssign will call indexOf, which checks the sorted property,
	and will do a sort, prior to a binary search to find the index.
	Whether key duplicates matter or not, is up to the programmer.
	
*/

struct KeyValueBlock(K,V, bool AUTOSORT = false)
{
    alias KeyValRec!(K,V) BlockRec;
	alias V[K]			  RealAA;
	alias KeyValueBlock!(K,V,AUTOSORT)  Records;


	static if (isSomeString!K)
	{
		static if (is(K==string))
		{
			alias const(char)[] LK;
		}
		else static if(is(K==wstring))
		{
			alias const(wchar)[] LK;
		}
		else static if(is(K==dstring))
		{
			alias const(dchar)[] LK;
		}
		else
			alias K LK;
	}
	else {
		alias K LK;
	}
	private	Array!BlockRec	records;
	static if (AUTOSORT)
	{
		private {
			bool	sorted_;
			bool	appendMode_;
		}
		/// Set this if really known that sorted property is incorrect
		void sorted(bool val) @property
		{
			sorted_ = val;
		}
		/// What the sorted state appears to be.
		bool sorted() const @property
		{
			return sorted_;
		}
		
		/** If true, opIndexAssign does append, rather than binary search for existing key
			Calling sort, will set this to false
		*/
		bool appendMode() const  @property 
		{
			return appendMode_;
		}
		/**  opIndexAssign appends if true. If false will search for existing key.
		Calling sort, will set this to false
			*/
		void appendMode(bool val) @property
		{
			appendMode_ = val;
		}
	}
public:

    uintptr_t length() const  @property  
    {
        return records.length;
    }
	
	/// Return true if adjacent keys are the same. Assume sorted
	intptr_t getDuplicateIndex()
	{
		auto blen = records.length;
		if (blen < 2)
			return -1;
		auto rp = records.constPtr();
		for(auto ix = 1; ix < blen; ix++)
		{
			if (rp[ix].id == rp[ix-1].id)
			{
				return ix;
			}
		}
		return -1;
	}
	ref auto atIndex(uintptr_t ix)
	{
		return records.constPtr[ix];
	}
	void capacity(uintptr_t cap) @property 
	{
		records.reserve(cap,true);
	}

	void reserve(uintptr_t cap, bool exact)
	{
		records.reserve(cap,exact);
	}

	/// Forced append at end
	void put(BlockRec r)
	{
		records.put(r);
		static if (AUTOSORT)
		{
			sorted_ = (records.length < 2);
		}
	}

    intptr_t indexOf(LK key)
    {
		static if (AUTOSORT)
		{
			if (!sorted_)
			{
				sorted_ = true;
				if (records.length > 1)
					records.sort;
			}
			uintptr_t iend = records.length;
			uintptr_t ibegin = 0;
			auto rptr = records.constPtr;
			while (ibegin < iend)
			{
				immutable imid = (iend + ibegin)/2;
				auto r = &rptr[imid];
				auto relation = typeid(K).compare(&r.id, &key);
				if (relation < 0)
				{
					ibegin = imid + 1;
				}
				else if (relation > 0)
				{
					iend = imid;
				}
				else 
					return imid;
			}
			return -1;
		}
		else {
			auto rp = records.constPtr();
			for(size_t k = 0; k < records.length; k++)
			{
				if (key == rp[k].id)
				   return k;
			}
			return -1;
		}
    }

	void remove(K key)
	{
        auto k = indexOf(key);
		if (k >= 0)
		{
			records[k] = BlockRec.init;
			records.pack(k);
		}
	}


	V get(K key, lazy V defaultVal)
	{
		auto ix = indexOf(cast(LK) key);
		if (ix < 0)
			return defaultVal;
		else
			return records.ptr[ix].value;
	}



    V opIndex(K key)
    {
		auto k = indexOf(key);
		if (k >= 0)
		{
			return records.ptr[k].value;
		}
		static if(isSomeString!V)
		{
			return null;
		}
		else {
			// hard to indicate a not found
			throw new AltStringError(text("opIndex not found in ", typeid(this).name));
		}
    }

	void setKeysValues(K[] keys, V[] values)
	in {
		assert((keys.length == values.length) && (keys.length > 0));
	}
	body
	{
		auto blen = keys.length;
		records.length = blen;
		auto wp = records.ptr();
		for(auto ix = 0; ix < blen; ix++, wp++)
		{
			wp.id = keys[ix];
			wp.value = values[ix];
		}
		static if (AUTOSORT)
		{
			sorted_ = (blen < 2);
		}
	}

    void opIndexAssign(V val, K key)
    {
		auto rec = BlockRec(key,val);
		static if (AUTOSORT)
		{
			if (!appendMode_)
			{
				auto k = indexOf(key);
				if (k >= 0)
				{
					records[k] = rec;
					return;
				}
			}
		}
		else {
			auto k = indexOf(key);
			if (k >= 0)
			{
				records[k] = rec;
				return;
			}
		}
		put(rec);
    }
	

    RealAA toAA()
    {
        RealAA aa;
        auto r = records.ptr();
        for(size_t k = 0; k < records.length; k++, r++)
        {
            aa[r.id] = r.value;
        }
        return aa;
    }

	/// shallow copy of contents
    Records dup()
    {
		Records result;
		result.records = this.records;
		return result;
    }

    V[] getValues(V[] valueArray)
    {
        auto slen = length;
        if (valueArray.length != slen)
            valueArray.length = slen;
        auto r = records.ptr();
        for(size_t k = 0; k < slen; k++, r++)
        {
            valueArray[k] = r.value;
        }
        return valueArray;
    }

	void explode(bool del)
	{
		records.free(del);
	}
    void clear()
    {
       records.clear();
    }

	const(BlockRec)[] sort() @property 
	{
		static if (AUTOSORT)
		{
			sorted_ = true;
			appendMode_ = false;
		}
		return records.sort;
	}

    int opApply(scope int delegate(const K, const V) dg) const
    {
        uint ct = 0;
        auto r = records.constPtr();
        for(size_t k = 0; k < records.length; k++, r++)
        {
            int result = dg(r.id, r.value);
            if (result)
                return result;
        }
        return 0;
    }
    V* opIn_r(ref K key)
    {
		immutable ix = indexOf(key);
		return (ix >= 0) ? &records.ptr[ix].value : null;
    }
    V* opIn_r(ref LK key)
    {
		immutable ix = indexOf(key);
		return (ix >= 0) ? &records.ptr[ix].value : null;
    }

	int opCmp(ref const(Records) ro) const 
	{
		return cast(int)records.opCmp(ro.records);
	}
}


unittest
{
	alias KeyValueBlock!(string,string,true)	KVB;
	
	KVB sb;

	Array!char output;
	

	void put(string s)
	{
		output.put(' ');
		output.put(s);
	}


	sb.appendMode = true;
	sb["version"] = "1.0";
	sb["standalone"] = "yes";
	sb["encoding"] = "utf-8";
	
	sb.sort();
	auto cd = sb;

    put(cd["version"]);
    put(cd["standalone"]);
    put(cd["encoding"]);

}
