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

decimal_length17 :: inline (v : u64) -> u32
{
	// This is slightly faster than a loop.
	// The average output length is 16.38 digits, so we check high-to-low.
	// Function precondition: v is not an 18, 19, or 20-digit number.
	// (17 digits are sufficient for round-tripping.)
	ryu_assert (v < 100000000000000000);
	if v >= 10000000000000000 then return 17;
	if v >=  1000000000000000 then return 16;
	if v >=   100000000000000 then return 15;
	if v >=    10000000000000 then return 14;
	if v >=     1000000000000 then return 13;
	if v >=      100000000000 then return 12;
	if v >=       10000000000 then return 11;
	if v >=        1000000000 then return 10;
	if v >=         100000000 then return  9;
	if v >=          10000000 then return  8;
	if v >=           1000000 then return  7;
	if v >=            100000 then return  6;
	if v >=             10000 then return  5;
	if v >=              1000 then return  4;
	if v >=               100 then return  3;
	if v >=                10 then return  2;
	return 1;
}

#scope_export

// A floating decimal representing m * 10^e.
F64_Decimal :: struct
{
	mantissa : u64;
	// Decimal exponent's range is -324 to 308
	// inclusive, and can fit in a short if needed.
	exponent : s32;
}

f64_to_decimal :: inline (ieee_mantissa : u64, ieee_exponent : u32) -> F64_Decimal
{
	// @Note (stefan): In Jai, casting rules are a bit different than in C,
	// this is why when we do in C:
	//     xx_modN = ((uint32_t)xx) - 10 * ((uint32_t) xx_divN);
	// in Jai, we'll do:
	//     xx_modN = cast (u32) (xx - 10 * xx_divN);
	e2 : s32 = ---;
	m2 : u64 = ---;
	if ieee_exponent == 0
	{
		// We subtract 2 so that the bounds computation has 2 additional bits.
		e2 = 1 - F64_BIAS - F64_MANTISSA_BITS - 2;
		m2 = ieee_mantissa;
	}
	else
	{
		e2 = cast (s32) ieee_exponent - F64_BIAS - F64_MANTISSA_BITS - 2;
		m2 = (1 << F64_MANTISSA_BITS) | ieee_mantissa;
	}
	even := (m2 & 1) == 0;
	accept_bounds := even;

#if DEBUG
	print ("-> % * 2^%\n", m2, e2 + 2);

	// Step 2: Determine the interval of valid decimal representations.
	mv := 4 * m2;
	// Implicit bool -> int conversion. True is 1, false is 0.
	mm_shift := cast (u32) (ieee_mantissa != 0 || ieee_exponent <= 1);
	// We would compute mp and mm like this:
	// uint64_t mp = 4 * m2 + 2;
	// uint64_t mm = mv - 1 - mmShift;

	// Step 3: Convert to a decimal power base using 128-bit arithmetic.
	vr : u64 = ---;
	vp : u64 = ---;
	vm : u64 = ---;
	e10 : s32 = ---;
	vm_is_trailing_zeroes := false;
	vr_is_trailing_zeroes := false;
	if e2 >= 0
	{
		// I tried special-casing q == 0, but there was no effect on performance.
		// This expression is slightly faster than max(0, log10Pow2(e2) - 1).
		q := log10pow2 (e2) - cast (u32) (e2 > 3);
		e10 = cast (s32) q;
		k := F64_POW5_INV_BITCOUNT + pow5bits (cast (s32) q) - 1;
		i := -e2 + cast (s32) q + k;
#if OPTIMIZE_SIZE
{
		pow5 : [2]u64 = ---;
		f64_compute_inv_pow5 (q, pow5.data);
		vr = mul_shift_all_64 (m2, pow5.data, i, *vp, *vm, mm_shift);
}
else
{
		vr = mul_shift_all_64 (m2, F64_POW5_INV_SPLIT[q].data, i, *vp, *vm, mm_shift);
}
#if DEBUG
{
		print ("% * 2^% / 10^%\n", mv, e2, q);
		print ("V+=%\nV =%\nV-=%\n", vp, vr, vm);
}
		if q <= 21
		{
			// This should use q <= 22, but I think 21 is also safe. Smaller values
			// may still be safe, but it's more difficult to reason about them.
			// Only one of mp, mv, and mm can be a multiple of 5, if any.
			mv_mod5 := cast (u32) (mv - 5 * div5 (mv));
			if mv_mod5 == 0
				vr_is_trailing_zeroes = multiple_of_power_of_5 (mv, q);
			else if accept_bounds
				// Same as min(e2 + (~mm & 1), pow5Factor(mm)) >= q
				// <=> e2 + (~mm & 1) >= q && pow5Factor(mm) >= q
				// <=> true && pow5Factor(mm) >= q, since e2 >= q.
				vm_is_trailing_zeroes = multiple_of_power_of_5 (mv - 1 - mm_shift, q);
			else
				vp -= cast (u64) multiple_of_power_of_5 (mv + 2, q);
		}
	}
	else
	{
		// This expression is slightly faster than max(0, log10Pow5(-e2) - 1).
		q := log10pow5 (-e2) - cast (u32) (-e2 > 1);
		e10 = cast (s32) q + e2;
		i := -e2 - cast (s32) q;
		k := pow5bits (i) - F64_POW5_BITCOUNT;
		j := cast (s32) q - k;
#if OPTIMIZE_SIZE
{
		pow5 : [2]u64 = ---;
		f64_compute_pow5 (cast (u32) i, pow5.data);
		vr = mul_shift_all_64 (m2, pow5.data, j, *vp, *vm, mm_shift);
}
else
{
		vr = mul_shift_all_64 (m2, F64_POW5_SPLIT[i].data, j, *vp, *vm, mm_shift);
}
#if DEBUG
{
		print ("% * 5^% / 10^%\n", mv, -e2, q);
		print ("% % % %\n", q, i, k, j);
		print ("V+=%\nV =%\nV-=%\n", vp, vr, vm);
}
		if q <= 1
		{
			// {vr,vp,vm} is trailing zeros if {mv,mp,mm} has at least q trailing 0 bits.
			// mv = 4 * m2, so it always has at least two trailing 0 bits.
			vr_is_trailing_zeroes = true;
			if accept_bounds
				// mm = mv - 1 - mmShift, so it has 1 trailing 0 bit iff mmShift == 1.
				vm_is_trailing_zeroes = mm_shift == 1;
			else
				// mp = mv + 2, so it always has at least one trailing 0 bit.
				vp -= 1;
		}
		else if q < 63
		{
			// We want to know if the full product has at least q trailing zeros.
			// We need to compute min(p2(mv), p5(mv) - e2) >= q
			// <=> p2(mv) >= q && p5(mv) - e2 >= q
			// <=> p2(mv) >= q (because -e2 >= q)
			vr_is_trailing_zeroes = multiple_of_power_of_2 (mv, q);
#if DEBUG
			print ("vr is trailing zeores=%\n", vr_is_trailing_zeroes);
		}
	}
#if DEBUG
{
	print ("e10=%\n", e10);
	print ("V+=%\nV =%\nV-=%\n", vp, vr, vm);
	print ("vm is trailing zeores=%\n", vm_is_trailing_zeroes);
	print ("vr is trailing zeores=%\n", vr_is_trailing_zeroes);
}

	// Step 4: Find the shortest decimal representation in the interval of valid representations.
	removed : s32 = 0;
	last_removed_digit : u8 = 0;
	output : u64 = ---;
	// On average, we remove ~2 digits.
	if vm_is_trailing_zeroes || vr_is_trailing_zeroes
	{
		// General case, which happens rarely (~0.7%).
		while true
		{
			vp_div10 := div10 (vp);
			vm_div10 := div10 (vm);
			if vp_div10 <= vm_div10
				break;
			vm_mod10 := cast (u32) (vm - 10 * vm_div10);
			vr_div10 := div10 (vr);
			vr_mod10 := cast (u32) (vr - 10 * vr_div10);
			vm_is_trailing_zeroes &= vm_mod10 == 0;
			vr_is_trailing_zeroes &= last_removed_digit == 0;
			last_removed_digit = cast (u8) vr_mod10;
			vr = vr_div10;
			vp = vp_div10;
			vm = vm_div10;
			removed += 1;
		}
#if DEBUG
{
		print ("V+=%\nV =%\nV-=%\n", vp, vr, vm);
		print ("d-10=%\n", vm_is_trailing_zeroes);
}
		if vm_is_trailing_zeroes
		{
			while true
			{
				vm_div10 := div10 (vm);
				vm_mod10 := cast (u32) (vm - 10 * vm_div10);
				if vm_mod10 != 0
					break;
				vp_div10 := div10 (vp);
				vr_div10 := div10 (vr);
				vr_mod10 := cast (u32) (vr - 10 * vr_div10);
				vr_is_trailing_zeroes &= last_removed_digit == 0;
				last_removed_digit = cast (u8) vr_mod10;
				vr = vr_div10;
				vp = vp_div10;
				vm = vm_div10;
				removed += 1;
			}
		}
#if DEBUG
{
		print ("% %\n", vr, last_removed_digit);
		print ("vr is trailing zeores=%\n", vr_is_trailing_zeroes);
}
		if vr_is_trailing_zeroes && last_removed_digit == 5 && vr % 2 == 0
			// Round even if the exact number is .....50..0.
			last_removed_digit = 4;
		// We need to take vr + 1 if vr is outside bounds or we need to round up.
		output = vr + cast (u64) ((vr == vm && (!accept_bounds || !vm_is_trailing_zeroes)) || last_removed_digit >= 5);
	}
	else
	{
		// Specialized for the common case (~99.3%). Percentages below are relative to this.
		round_up := false;
		vp_div100 := div100 (vp);
		vm_div100 := div100 (vm);
		if vp_div100 > vm_div100	// Optimization: remove two digits at a time (~86.2%).
		{
			vr_div100 := div100 (vr);
			vr_mod100 := cast (u32) (vr - 100 * vr_div100);
			round_up = vr_mod100 >= 50;
			vr = vr_div100;
			vp = vp_div100;
			vm = vm_div100;
			removed += 2;
		}
		// Loop iterations below (approximately), without optimization above:
		// 0: 0.03%, 1: 13.8%, 2: 70.6%, 3: 14.0%, 4: 1.40%, 5: 0.14%, 6+: 0.02%
		// Loop iterations below (approximately), with optimization above:
		// 0: 70.6%, 1: 27.8%, 2: 1.40%, 3: 0.14%, 4+: 0.02%
		while true
		{
			vp_div10 := div10 (vp);
			vm_div10 := div10 (vm);
			if vp_div10 <= vm_div10
				break;
			vr_div10 := div10 (vr);
			vr_mod10 := cast (u32) (vr - 10 * vr_div10);
			round_up = vr_mod10 >= 5;
			vr = vr_div10;
			vp = vp_div10;
			vm = vm_div10;
			removed += 1;
		}
#if DEBUG
{
		print ("% round_up=%\n", vr, round_up);
		print ("vr is trailing zeores=%\n", vr_is_trailing_zeroes);
}
		// We need to take vr + 1 if vr is outside bounds or we need to round up.
		output = vr + cast (u64) (vr == vm || round_up);
	}
	exp := e10 + removed;

#if DEBUG
{
	print ("V+=%\nV =%\nV-=%\n", vp, vr, vm);
	print ("O=%\n", output);
	print ("EXP=%\n", exp);
}

	result : F64_Decimal = ---;
	result.exponent = exp;
	result.mantissa = output;

	return result;
}

#scope_file

to_chars :: inline (v : F64_Decimal, sign : bool, result : *u8) -> s32
{
	// Step 5: Print the decimal representation.
	index : s32 = 0;
	if sign
	{
		result[index] = #char "-";
		index += 1;
	}

	output := v.mantissa;
	olength := cast (s32) decimal_length17 (output);
	total_length := index + olength;
	{
		exp := v.exponent + cast (s32) olength - 1;
		if exp < 0
		{
			total_length += 1;	// Sign
			exp = -exp;
		}
		if exp < 10
			total_length += 1;
		else if exp < 100
			total_length += 2;
		else
			total_length += 3;
	}

#if DEBUG
{
	print ("DIGITS=%\n", v.mantissa);
	print ("OLEN=%\n", olength);
	print ("EXP=%\n", v.exponent + olength);
}
	// Print the decimal digits.
	// The following code is equivalent to:
	// for (uint32_t i = 0; i < olength - 1; ++i) {
	//   const uint32_t c = output % 10; output /= 10;
	//   result[index + olength - i] = (char) ('0' + c);
	// }
	// result[index] = '0' + output % 10;

	i : s32 = 0;
	// We prefer 32-bit operations, even on 64-bit platforms.
	// We have at most 17 digits, and uint32_t can store 9 digits.
	// If output doesn't fit into uint32_t, we cut off 8 digits,
	// so the rest will fit into uint32_t.
	if (output >> 32) != 0
	{
		// Expensive 64-bit division.
		q := div1e8 (output);
		output2 := cast (u32) (output - 100000000 * q);
		output = q;

		c := output2 % 10000;
		output2 /= 10000;
		d := output2 % 10000;
		c0 := (c % 100) << 1;
		c1 := (c / 100) << 1;
		d0 := (d % 100) << 1;
		d1 := (d / 100) << 1;
		memcpy (result + index + olength - i - 1, DIGIT_TABLE.data + c0, 2);
		memcpy (result + index + olength - i - 3, DIGIT_TABLE.data + c1, 2);
		memcpy (result + index + olength - i - 5, DIGIT_TABLE.data + d0, 2);
		memcpy (result + index + olength - i - 7, DIGIT_TABLE.data + d1, 2);
		i += 8;
	}
	output2 := cast (u32) output;
	while output2 >= 10000
	{
		c := output2 % 10000;
		output2 /= 10000;
		c0 := (c % 100) << 1;
		c1 := (c / 100) << 1;
		memcpy (result + index + olength - i - 1, DIGIT_TABLE.data + c0, 2);
		memcpy (result + index + olength - i - 3, DIGIT_TABLE.data + c1, 2);
		i += 4;
	}
	if output2 >= 100
	{
		c := (output2 % 100) << 1;
		output2 /= 100;
		memcpy (result + index + olength - i - 1, DIGIT_TABLE.data + c, 2);
		i += 2;
	}
	if output2 >= 10
	{
		c := output2 << 1;
		// We can't use memcpy here: the decimal dot goes between these two digits.
		result[index + olength - i] = DIGIT_TABLE[c + 1];
		result[index] = DIGIT_TABLE[c];
	}
	else
	{
		result[index] = cast (u8) (#char "0" + output2);
	}

	// Print the decimal point if needed.
	if olength > 1
	{
		result[index + 1] = #char ".";
		index += olength + 1;
	}
	else
	{
		index += 1;
	}

	// Print the exponent.
	result[index] = #char "e";
	index += 1;
	exp := v.exponent + olength - 1;
	if exp < 0
	{
		result[index] = #char "-";
		index += 1;
		exp = -exp;
	}

	if exp >= 100
	{
		c := exp % 10;
		memcpy (result + index, DIGIT_TABLE.data + 2 * (exp / 10), 2);
		result[index + 2] = cast (u8) (#char "0" + c);
		index += 3;
	}
	else if exp >= 10
	{
		memcpy (result + index, DIGIT_TABLE.data + 2 * exp, 2);
		index += 2;
	}
	else
	{
		result[index] = cast (u8) (#char "0" + exp);
		index += 1;
	}

	return index;
}

f64_to_decimal_small_int :: inline (ieee_mantissa : u64, ieee_exponent : u32, v : *F64_Decimal) -> bool
{
	m2 := (1 << F64_MANTISSA_BITS) | ieee_mantissa;
	e2 := cast (s32) ieee_exponent - F64_BIAS - F64_MANTISSA_BITS;

	if e2 > 0
		// f = m2 * 2^e2 >= 2^53 is an integer.
		// Ignore this case for now.
		return false;
	if e2 < -52
		// f < 1
		return false;

	// Since 2^52 <= m2 < 2^53 and 0 <= -e2 <= 52: 1 <= f = m2 / 2^-e2 < 2^53.
	// Test if the lower -e2 bits of the significand are 0, i.e. whether the fraction is 0.
	mask := cast (u64) (1 << -e2) - 1;
	fraction := m2 & mask;
	if fraction != 0
		return false;
	
	// f is an integer in the range [1, 2^53).
	// Note: mantissa might contain trailing (decimal) 0's.
	// Note: since 2^53 < 10^16, there is no need to adjust decimalLength17().
	v.mantissa = m2 >> -e2;
	v.exponent = 0;

	return true;
}

#scope_export

f64_to_shortest_buffered :: (f : f64, result : *u8) -> s32
{
	// Step 1: Decode the floating-point number, and unify normalized and subnormal cases.
	bits := f64_to_bits (f);

#if DEBUG
{
	print ("IN=");
	for < bit : 63..0
		print ("%", ((bits >> bit) & 1));
	print ("\n");
}
	// Decode bits into sign, mantissa, and exponent.
	ieee_sign := cast (bool) ((bits >> (F64_MANTISSA_BITS + F64_EXPONENT_BITS)) & 1);
	ieee_mantissa := bits & ((1 << F64_MANTISSA_BITS) - 1);
	ieee_exponent := cast (u32) ((bits >> F64_MANTISSA_BITS) & ((1 << F64_EXPONENT_BITS) - 1));
	// Case distinction; exit early for the easy cases.
	if ieee_exponent == ((1 << F64_EXPONENT_BITS) - 1) || (ieee_exponent == 0 && ieee_mantissa == 0)
		return copy_special_str (result, ieee_sign, ieee_exponent != 0, ieee_mantissa != 0);

	v : F64_Decimal = ---;
	is_small_int := f64_to_decimal_small_int (ieee_mantissa, ieee_exponent, *v);
	if is_small_int
	{
		// For small integers in the range [1, 2^53), v.mantissa might contain trailing (decimal) zeros.
		// For scientific notation we need to move these zeros into the exponent.
		// (This is not needed for fixed-point notation, so it might be beneficial to trim
		// trailing zeros in to_chars only if needed - once fixed-point notation output is implemented.)
		while true
		{
			q := div10 (v.mantissa);
			r := cast (u32) (v.mantissa - 10 * q);
			if r != 0
				break;
			v.mantissa = q;
			v.exponent += 1;
		}
	}
	else
	{
		v = f64_to_decimal (ieee_mantissa, ieee_exponent);
	}

	return to_chars (v, ieee_sign, result);
}

f64_to_shortest :: inline (f : f64, allocator : Allocator) -> string #must
{
	result : string = ---;
	result.data = allocator.proc (.ALLOCATE, 25, 0, null, allocator.data);
	result.count = f64_to_shortest_buffered (f, result.data);
	
	return result;
}
