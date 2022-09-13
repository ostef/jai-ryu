// Translation of the Ryū: Fast Float-to-String Conversion algorithm to Jai.
// The original paper can be found here:             https://dl.acm.org/doi/10.1145/3296979.3192369
// The revisited Ryū printf paper can be found here: https://dl.acm.org/doi/10.1145/3360595
// The original C code can be found here:            https://github.com/ulfjack/ryu
// under the following license:
//
// Copyright 2019 Ulf Adams
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

#assert !OPTIMIZE_SIZE "OPTIMIZE_SIZE is only partially implemented. Don't import string to float with OPTIMIZE_SIZE on.";

#scope_file

floor_log2 :: inline (value : u64) -> s32
#no_context
{
	index : u64 = 64;
	#asm
	{
		bsr.q	index, value;
	}

	return cast (s32) index;
}

max :: (a : s32, b : s32) -> s32
#no_context
{
	if a < b
		return b;
	return a;
}

bits_to_f64 :: (bits : u64) -> f64
#no_context
{
	f : f64 = ---;
	memcpy (*f, *bits, size_of (f64));

	return f;
}

#scope_export

string_to_f64 :: inline (str : string, using fmt := Format.{}) -> value : f64, status : Parse_Status, bytes_read : s32
#no_context
{
	value, status, bytes_read := string_to_f64 (str.data, cast (s32) str.count, fmt);

	return value, status, bytes_read;
}

string_to_f64 :: (buffer : *u8, len : s32, using fmt := Format.{}) -> value : f64, status : Parse_Status, bytes_read : s32
#no_context
{
	if len == 0
		return 0.0, .INPUT_TOO_SHORT, 0;

	m10digits : s32 = 0;
	e10digits : s32 = 0;
	dot_index := len;
	e_index   := len;
	m10 : u64 = 0;
	e10 : s32 = 0;
	signed_m := false;
	signed_e := false;
	i : s32 = 0;

	if len >= cast (s32) nan_string.count && memcmp (buffer, nan_string.data, nan_string.count) == 0
	{
		i += cast (s32) nan_string.count;
		ieee := (cast (u64) signed_m) << (F64_EXPONENT_BITS + F64_MANTISSA_BITS) | (0x7ff << F64_MANTISSA_BITS) | 1;

		return bits_to_f64 (ieee), .SUCCESS, i;
	}

	if buffer[i] == #char "-"
	{
		signed_m = true;
		i += 1;
	}
	else if buffer[i] == #char "+"
		i += 1;

	if len - i >= cast (s32) inf_string.count && memcmp (buffer + i, inf_string.data, inf_string.count) == 0
	{
		i += cast (s32) inf_string.count;
		ieee := (cast (u64) signed_m) << (F64_EXPONENT_BITS + F64_MANTISSA_BITS) | (0x7ff << F64_MANTISSA_BITS);

		return bits_to_f64 (ieee), .SUCCESS, i;
	}

	while i < len
	{
		c := buffer[i];

		if c == decimal_separator
		{
			if dot_index != len
				return 0.0, .MALFORMED_INPUT, i;
			dot_index = i;
			i += 1;

			continue;
		}

		if c < #char "0" || c > #char "9"
			break;

		if m10digits >= 17
			return 0.0, .INPUT_TOO_LONG, i;

		m10 = 10 * m10 + (c - #char "0");
		if m10 != 0
			m10digits += 1;

		i += 1;
	}

	if i == 0
		return 0.0, .MALFORMED_INPUT, i;

	if i < len && (buffer[i] == #char "e" || buffer[i] == #char "E")
	{
		e_index = i;
		i += 1;

		if i < len && (buffer[i] == #char "-" || buffer[i] == #char "+")
		{
			signed_e = buffer[i] == #char "-";
			i += 1;
		}

		while i < len
		{
			c := buffer[i];

			if c < #char "0" || c > #char "9"
				break;

			if e10digits > 3
				return 0.0, .INPUT_TOO_LONG, i;

			e10 = 10 * e10 + (c - #char "0");
			if e10 != 0
				e10digits += 1;

			i += 1;
		}
	}

	if e_index   == len
		e_index = i;

	if dot_index == len
		dot_index = i;

	if signed_e
		e10 = -e10;

	if dot_index < e_index
		e10 -= e_index - dot_index - 1;

	if m10 == 0
		return (ifx signed_m then -0.0 else 0.0), .SUCCESS, i;

	#if DEBUG
	{
		str_buff : string = ---;
		str_buff.data = buffer;
		str_buff.count = len;

		print ("Input=%\n", str_buff);
		print ("m10digits = %\n", m10digits);
		print ("e10digits = %\n", e10digits);
		print ("m10 * 10^e10 = % * 10^%\n", m10, e10);
	}

	if m10digits + e10 <= -324 || m10 == 0
	{
		// Number is less than 1e-324, which should be rounded down to 0; return +/-0.0.
		return (ifx signed_m then -0.0 else 0.0), .SUCCESS, i;
	}

	if m10digits + e10 >= 310
	{
		// Number is larger than 1e+309, which should be rounded to +/-Infinity.
		ieee := (cast (u64) signed_m) << (F64_EXPONENT_BITS + F64_MANTISSA_BITS) | (0x7ff << F64_MANTISSA_BITS);

		return bits_to_f64 (ieee), .SUCCESS, i;
	}

	// Convert to binary float m2 * 2^e2, while retaining information about whether the conversion
	// was exact (trailingZeros).
	e2 : s32 = ---;
	m2 : u64 = ---;
	trailing_zeroes : bool = ---;
	if e10 >= 0
	{
		// The length of m * 10^e in bits is:
		//   log2(m10 * 10^e10) = log2(m10) + e10 log2(10) = log2(m10) + e10 + e10 * log2(5)
		//
		// We want to compute the DOUBLE_MANTISSA_BITS + 1 top-most bits (+1 for the implicit leading
		// one in IEEE format). We therefore choose a binary output exponent of
		//   log2(m10 * 10^e10) - (DOUBLE_MANTISSA_BITS + 1).
		//
		// We use floor(log2(5^e10)) so that we get at least this many bits; better to
		// have an additional bit than to not have enough bits.
		e2 = floor_log2 (m10) + e10 + log2pow5 (e10) - (F64_MANTISSA_BITS + 1);

		// We now compute [m10 * 10^e10 / 2^e2] = [m10 * 5^e10 / 2^(e2-e10)].
		// To that end, we use the DOUBLE_POW5_SPLIT table.
		j := e2 - e10 - ceil_log2pow5 (e10) + F64_POW5_BITCOUNT;
		ryu_assert (j >= 0);

#if OPTIMIZE_SIZE
{
		pow5 : [2]u64 = ---;
		f64_compute_pow5 (cast (u32) e10, pow5.data);
		m2 = mul_shift_64 (m10, pow5.data, j);
}
else
{
		ryu_assert (e10 < F64_POW5_TABLE_SIZE);
		m2 = mul_shift_64 (m10, F64_POW5_SPLIT[e10].data, j);
}

		// We also compute if the result is exact, i.e.,
		//   [m10 * 10^e10 / 2^e2] == m10 * 10^e10 / 2^e2.
		// This can only be the case if 2^e2 divides m10 * 10^e10, which in turn requires that the
		// largest power of 2 that divides m10 + e10 is greater than e2. If e2 is less than e10, then
		// the result must be exact. Otherwise we use the existing multipleOfPowerOf2 function.
		trailing_zeroes = e2 < e10 || (e2 - e10 < 64 && multiple_of_power_of_2 (m10, cast (u32) (e2 - e10)));
	}
	else
	{
		e2 = floor_log2 (m10) + e10 - ceil_log2pow5 (-e10) - (F64_MANTISSA_BITS + 1);
		j := e2 - e10 + ceil_log2pow5 (-e10) - 1 + F64_POW5_INV_BITCOUNT;

#if OPTIMIZE_SIZE
{
		pow5 : [2]u64 = ---;
		f64_compute_inv_pow5 (cast (u32) -e10, pow5.data);
		m2 = mul_shift_64 (m10, pow5.data, j);
}
else
{
		ryu_assert (-e10 < F64_POW5_INV_TABLE_SIZE);
		m2 = mul_shift_64 (m10, F64_POW5_INV_SPLIT[-e10].data, j);
}

		trailing_zeroes = multiple_of_power_of_5 (m10, cast (u32) -e10);
	}

	#if DEBUG
	{
		print ("m2 * 2^e2 = % * 2^%\n", m2, e2);
	}

	// Compute the final IEEE exponent.
	ieee_e2 := cast (u32) max (0, e2 + F64_BIAS + floor_log2 (m2));
	if ieee_e2 > 0x7fe
	{
		// Final IEEE exponent is larger than the maximum representable; return +/-Infinity.
		ieee := (cast (u64) signed_m) << (F64_EXPONENT_BITS + F64_MANTISSA_BITS) | (0x7ff << F64_MANTISSA_BITS);

		return bits_to_f64 (ieee), .SUCCESS, i;
	}

	// We need to figure out how much we need to shift m2. The tricky part is that we need to take
	// the final IEEE exponent into account, so we need to reverse the bias and also special-case
	// the value 0.
	shift := cast (s64) (ifx ieee_e2 == 0 then 1 else ieee_e2) - e2 - F64_BIAS - F64_MANTISSA_BITS;
	ryu_assert (shift >= 0);

	#if DEBUG
	{
		print ("ieee_e2 = %\n", ieee_e2);
		print ("shift = %\\n", shift);
	}

	// We need to round up if the exact value is more than 0.5 above the value we computed. That's
	// equivalent to checking if the last removed bit was 1 and either the value was not just
	// trailing zeros or the result would otherwise be odd.
	//
	// We need to update trailingZeros given that we have the exact output exponent ieee_e2 now.
	trailing_zeroes &= (m2 & cast (u64) ((1 << (shift - 1)) - 1)) == 0;
	last_removed_bit := (m2 >> (shift - 1)) & 1;
	round_up := last_removed_bit != 0 && (!trailing_zeroes || (((m2 >> shift) & 1) != 0));

	#if DEBUG
	{
		print ("round_up = %\n", round_up);
		print ("ieee_m2 = %\n", (m2 >> shift) + cast (u64) round_up);
	}

	ieee_m2 : u64  = (m2 >> shift) + cast (u64) round_up;
	ryu_assert (ieee_m2 <= (1 << (F64_MANTISSA_BITS + 1)));
	ieee_m2 &= (1 << F64_MANTISSA_BITS) - 1;

	if ieee_m2 == 0 && round_up
	{
		// Due to how the IEEE represents +/-Infinity, we don't need to check for overflow here.
		ieee_e2 += 1;
	}

	ieee := ((((cast (u64) signed_m) << F64_EXPONENT_BITS) | cast (u64) ieee_e2) << F64_MANTISSA_BITS) | ieee_m2;

	return bits_to_f64 (ieee), .SUCCESS, i;
}
