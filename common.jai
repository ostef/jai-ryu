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

F32_MANTISSA_BITS :: 23;
F32_EXPONENT_BITS :: 8;
F32_BIAS          :: 127;
F64_MANTISSA_BITS :: 52;
F64_EXPONENT_BITS :: 11;
F64_BIAS          :: 1023;

ryu_assert :: (assertion : bool, location := #caller_location) #expand
#no_context
{
	if !assertion
	{
		write_string (location.fully_pathed_filename);
		write_string (":");
		write_number (location.line_number);
		write_string (",");
		write_number (location.character_number);
		write_string (": Assertion failed!\n");
		debug_break ();
	}
}

// Returns the number of decimal digits in v, which must not contain more than 9 digits.
decimal_length9 :: inline (v : u32) -> u32 #must
#no_context
{
	// Function precondition: v is not a 10-digit number.
	// (f2s: 9 digits are sufficient for round-tripping.)
	// (d2fixed: We print 9-digit blocks.)
	ryu_assert (v < 1000000000);
	if v >= 100000000 then return 9;
	if v >=  10000000 then return 8;
	if v >=   1000000 then return 7;
	if v >=    100000 then return 6;
	if v >=     10000 then return 5;
	if v >=      1000 then return 4;
	if v >=       100 then return 3;
	if v >=        10 then return 2;
	
	return 1;
}

// Returns e == 0 ? 1 : [log_2(5^e)]; requires 0 <= e <= 3528.
log2pow5 :: inline (e : s32) -> s32 #must
#no_context
{
	// This approximation works up to the point that the multiplication overflows at e = 3529.
	// If the multiplication were done in 64 bits, it would fail at 5^4004 which is just greater
	// than 2^9297.
	ryu_assert (e >= 0);
	ryu_assert (e <= 3528);

	return cast (s32) ((cast (u32) e * 1217359) >> 19);
}

// Returns e == 0 ? 1 : ceil(log_2(5^e)); requires 0 <= e <= 3528.
pow5bits :: inline (e : s32) -> s32 #must
#no_context
{
	// This approximation works up to the point that the multiplication overflows at e = 3529.
	// If the multiplication were done in 64 bits, it would fail at 5^4004 which is just greater
	// than 2^9297.
	ryu_assert (e >= 0);
	ryu_assert (e <= 3528);

	return cast (s32) ((cast (u32) e * 1217359) >> 19) + 1;
}

// Returns e == 0 ? 1 : ceil(log_2(5^e)); requires 0 <= e <= 3528.
ceil_log2pow5 :: inline (e : s32) -> s32 #must
#no_context
{
	return log2pow5 (e) + 1;
}

// Returns floor(log_10(2^e)); requires 0 <= e <= 1650.
log10pow2 :: inline (e : s32) -> u32 #must
#no_context
{
	// The first value this approximation fails for is 2^1651 which is just greater than 10^297.
	ryu_assert (e >= 0);
	ryu_assert (e <= 1650);

	return (cast (u32) e * 78913) >> 18;
}

// Returns floor(log_10(5^e)); requires 0 <= e <= 2620.
log10pow5 :: inline (e : s32) -> u32 #must
#no_context
{
	// The first value this approximation fails for is 5^2621 which is just greater than 10^1832.
	ryu_assert (e >= 0);
	ryu_assert (e <= 2620);

	return (cast (u32) e * 732923) >> 20;
}

copy_special_str :: inline (result : *u8, sign : bool, exponent : bool, mantissa : bool) -> s32
#no_context
{
	if mantissa
	{
		memcpy (result, "NaN".data, "NaN".count);

		return cast (s32) "NaN".count;
	}
	index : s32 = 0;
	if sign
	{
		result[index] = #char "-";
		index += 1;
	}
	if exponent
	{
		memcpy (result + index, "Inf".data, "Inf".count);

		return index + cast (s32) "Inf".count;
	}
	memcpy (result + index, "0e0".data, 3);
	
	return index + 3;
}

f32_to_bits :: inline (f : f32) -> u32 #must
#no_context
{
	bits : u32 = ---;
	memcpy (*bits, *f, size_of (f32));

	return bits;
}

f64_to_bits :: inline (f : f64) -> u64 #must
#no_context
{
	bits : u64 = ---;
	memcpy (*bits, *f, size_of (f64));

	return bits;
}
