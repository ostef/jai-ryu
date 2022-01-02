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

pow5factor :: inline (value : u32) -> u32 #must
{
	count : u32;
	while true
	{
		ryu_assert (value != 0);
		q := value / 5;
		r := value % 5;
		if r != 0
			break;
		value = q;
		count += 1;
	}

	return count;
}

// Returns true if value is divisible by 5^p.
multiple_of_power_of_5 :: inline (value : u32, p : u32) -> bool #must
{
	return pow5factor (value) >= p;
}

// Returns true if value is divisible by 2^p.
multiple_of_power_of_2 :: inline (value : u32, p : u32) -> bool #must
{
	return (value & ((1 << p) - 1)) == 0;
}

// It seems to be slightly faster to avoid uint128_t here, although the
// generated code for uint128_t looks slightly nicer.
mul_shift :: inline (m : u32, factor : u64, shift : s32) -> u32 #must
{
	ryu_assert (shift > 32);

	factor_lo := cast, no_check (u32) factor;
	factor_hi := cast, no_check (u32) (factor >> 32);
	bits0     := cast (u64) m * factor_lo;
	bits1     := cast (u64) m * factor_hi;
	sum         := (bits0 >> 32) + bits1;
	shifted_sum := sum >> (shift - 32);
	ryu_assert (shifted_sum <= cast (u32) 0xffffffff);

	return cast (u32) shifted_sum;
}

mul_pow5_inv_div_pow2 :: inline (m : u32, q : u32, j : s32) -> u32 #must
{
	return mul_shift (m, F32_POW5_INV_SPLIT[q], j);
}

mul_pow5_div_pow2 :: inline (m : u32, i : u32, j : s32) -> u32 #must
{
	return mul_shift (m, F32_POW5_SPLIT[i], j);
}
