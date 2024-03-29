// Translation of the Ryū: Fast Float-to-String Conversion algorithm to Jai.
// The original paper can be found here:             https://dl.acm.org/doi/10.1145/3296979.3192369
// The revisited Ryū printf paper can be found here: https://dl.acm.org/doi/10.1145/3360595
// The original C code can be found here:            https://github.com/ulfjack/ryu
// under the following license:
//
// Copyright 2018 Ulf Adams
//
// The contents of this file may be used under the terms of the Apache License,
// Version 2.0.
//
//    (See accompanying file LICENSE-Apache or copy at
//     http://www.apache.org/licenses/LICENSE-2.0)
//
// Alternatively, the contents of this file may be used under the terms of
// the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE-Boost or copy at
//     https://www.boost.org/LICENSE_1_0.txt)
//
// Unless required by applicable law or agreed to in writing, this software
// is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.

#scope_module

#if USE_64BIT_INSTRUCTIONS
{

umul128 :: inline (left : u64, right : u64, product_hi : *u64) -> u64
#no_context
{
	low := left;
	high : u64 = ---;
	#asm
	{
		right === c;
		low   === a;
		high  === d;
		mul.q	high, low, right;
	};
	<<product_hi = high;

	return low;
}

}
else	// USE_64BIT_INSTRUCTIONS
{

umul128 :: inline (a : u64, b : u64, product_hi : *u64) -> u64
#no_context
{
	a_lo := cast, trunc (u32) a;
	a_hi := cast, trunc (u32) (a >> 32);
	b_lo := cast, trunc (u32) b;
	b_hi := cast, trunc (u32) (b >> 32);

	#if DEBUG
	{
		print ("a_lo=%\n", a_lo);
		print ("a_hi=%\n", a_hi);
		print ("b_lo=%\n", b_lo);
		print ("b_hi=%\n", b_hi);
	}

	b00 := cast, no_check (u64) a_lo * b_lo;
	b01 := cast, no_check (u64) a_lo * b_hi;
	b10 := cast, no_check (u64) a_hi * b_lo;
	b11 := cast, no_check (u64) a_hi * b_hi;

	b00_lo := cast, trunc (u32) b00;
	b00_hi := cast, trunc (u32) (b00 >> 32);

	mid1 := b10 + b00_hi;
	mid1_lo := cast, trunc (u32) mid1;
	mid1_hi := cast, trunc (u32) (mid1 >> 32);

	mid2 := b01 + mid1_lo;
	mid2_lo := cast, trunc (u32) mid2;
	mid2_hi := cast, trunc (u32) (mid2 >> 32);

	p_hi := b11 + mid1_hi + mid2_hi;
	// @Note (stefan): << has priority over the cast.
	p_lo := ((cast, no_check (u64) mid2_lo) << 32) | b00_lo;

	<<product_hi = p_hi;
	
	return p_lo;
}

}	// USE_64BIT_INSTRUCTIONS

shiftright128 :: inline (lo : u64, hi : u64, dist : u32) -> u64 #must
#no_context
{
	// We don't need to handle the case dist >= 64 here (see above).
	ryu_assert (dist < 64);
	ryu_assert (dist > 0);

	return (hi << (64 - dist)) | (lo >> dist);
}

// @Note (stefan): div5, div10, div100, div1e8, div1e9 and mod1e9
// all exist so we can have 32-bit versions for 32-bit systems.
// This is unnecessary in Jai, at least for now, since 32-bit systems are note supported.
// We still have these functions for readability.

div5 :: inline (x : u64) -> u64 #must
#no_context
{
	return x / 5;
}

div10 :: inline (x : u64) -> u64 #must
#no_context
{
	return x / 10;
}

div100 :: inline (x : u64) -> u64 #must
#no_context
{
	return x / 100;
}

div1e8 :: inline (x : u64) -> u64 #must
#no_context
{
	return x / 100000000;
}

div1e9 :: inline (x : u64) -> u64 #must
#no_context
{
	return x / 1000000000;
}

mod1e9 :: inline (x : u64) -> u32 #must
#no_context
{
	return cast (u32) (x - 1000000000 * div1e9 (x));
}

pow5factor :: inline (value : u64) -> u32 #must
#no_context
{
	m_inv_5 : u64 = 14757395258967641293;	// 5 * m_inv_5 = 1 (mod 2^64)
	n_div_5 : u64 = 3689348814741910323;	// #{ n | n = 0 (mod 2^64) } = 2^64 / 5
	count : u32 = 0;

	while true
	{
		ryu_assert (value != 0);
		value *= m_inv_5;
		if value > n_div_5
			break;
		count += 1;
	}
	
	return count;
}

// Returns true if value is divisible by 5^p.
multiple_of_power_of_5 :: inline (value : u64, p : u32) -> bool #must
#no_context
{
	// I tried a case distinction on p, but there was no performance difference.
	return pow5factor (value) >= p;
}

// Returns true if value is divisible by 2^p.
multiple_of_power_of_2 :: inline (value : u64, p : u32) -> bool #must
#no_context
{
	ryu_assert (value != 0);
	ryu_assert (p < 64);
	
	return (value & cast (u64) ((1 << p) - 1)) == 0;
}

// We need a 64x128-bit multiplication and a subsequent 128-bit shift.
// Multiplication:
//   The 64-bit factor is variable and passed in, the 128-bit factor comes
//   from a lookup table. We know that the 64-bit factor only has 55
//   significant bits (i.e., the 9 topmost bits are zeros). The 128-bit
//   factor only has 124 significant bits (i.e., the 4 topmost bits are
//   zeros).
// Shift:
//   In principle, the multiplication result requires 55 + 124 = 179 bits to
//   represent. However, we then shift this value to the right by j, which is
//   at least j >= 115, so the result is guaranteed to fit into 179 - 115 = 64
//   bits. This means that we only need the topmost 64 significant bits of
//   the 64x128-bit multiplication.
//
// There are several ways to do this:
// 1. Best case: the compiler exposes a 128-bit type.
//    We perform two 64x64-bit multiplications, add the higher 64 bits of the
//    lower result to the higher result, and shift by j - 64 bits.
//
//    We explicitly cast from 64-bit to 128-bit, so the compiler can tell
//    that these are only 64-bit inputs, and can map these to the best
//    possible sequence of assembly instructions.
//    x64 machines happen to have matching assembly instructions for
//    64x64-bit multiplications and 128-bit shifts.
//
// 2. Second best case: the compiler exposes intrinsics for the x64 assembly
//    instructions mentioned in 1.
//
// 3. We only have 64x64 bit instructions that return the lower 64 bits of
//    the result, i.e., we have to use plain C.
//    Our inputs are less than the full width, so we have three options:
//    a. Ignore this fact and just implement the intrinsics manually.
//    b. Split both into 31-bit pieces, which guarantees no internal overflow,
//       but requires extra work upfront (unless we change the lookup table).
//    c. Split only the first factor into 31-bit pieces, which also guarantees
//       no internal overflow, but requires extra work since the intermediate
//       results are not perfectly aligned.

mul_shift_64 :: inline (m : u64, mul : *u64, j : s32) -> u64 #must
#no_context
{
	// m is maximum 55 bits
	high1 : u64 = ---;						// 128
	low1 := umul128 (m, mul[1], *high1);	// 64
	high0 : u64 = ---;						// 64
	umul128 (m, mul[0], *high0);			// 8

	sum := high0 + low1;
	if sum < high0
		high1 += 1;	// overflow into high1

	return shiftright128 (sum, high1, cast (u32) (j - 64));
}

#if USE_64BIT_INSTRUCTIONS
{

mul_shift_all_64 :: inline (m : u64, mul : *u64, j : s32, vp : *u64, vm : *u64, mm_shift : u32) -> u64
#no_context
{
	<<vp = mul_shift_64 (4 * m + 2, mul, j);
	<<vm = mul_shift_64 (4 * m - 1 - mm_shift, mul, j);

	return mul_shift_64 (4 * m, mul, j);
}

}
else	// USE_64BIT_INSTRUCTIONS
{

// This is faster if we don't have a 64x64->128-bit multiplication.
mul_shift_all_64 :: inline (m : u64, mul : *u64, j : s32, vp : *u64, vm : *u64, mm_shift : u32) -> u64
#no_context
{
	m <<= 1;
	// m is maximum 55 bits
	tmp : u64 = ---;
	lo := umul128 (m, mul[0], *tmp);
	hi : u64 = ---;
	mid := tmp + umul128 (m, mul[1], *hi);
	hi += cast (u64) (mid < tmp);	// overflow into hi

	lo2 := lo + mul[0];
	mid2 := mid + mul[1] + cast (u64) (lo2 < lo);
	hi2 := hi + cast (u64) (mid2 < mid);
	<<vp = shiftright128 (mid2, hi2, cast (u32) (j - 64 - 1));

	if mm_shift == 1
	{
		lo3 := lo - mul[0];
		mid3 := mid - mul[1] - cast (u64) (lo3 > lo);
		hi3 := hi - cast (u64) (mid3 > mid);
		<<vm = shiftright128 (mid3, hi3, cast (u32) (j - 64 - 1));
	}
	else
	{
		lo3 := lo + lo;
		mid3 := mid + mid + cast (u64) (lo3 < lo);
		hi3 := hi + hi + cast (u64) (mid3 < mid);
		lo4 := lo3 - mul[0];
		mid4 := mid3 - mul[1] - cast (u64) (lo4 > lo3);
		hi4 := hi3 - cast (u64) (mid4 > mid3);
		<<vm = shiftright128 (mid4, hi4, cast (u32) (j - 64));
	}

	return shiftright128 (mid, hi, cast (u32) (j - 64 - 1));
}

}	// USE_64BIT_INSTRUCTIONS
