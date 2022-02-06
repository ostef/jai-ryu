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

#scope_file

POW10_ADDITIONAL_BITS :: 120;

mul_shift_mod1e9 :: inline (m : u64, mul : *u64, j : s32) -> u32
{
#if DEBUG
{
	print ("mul[0]=%\n", mul[0]);
	print ("mul[1]=%\n", mul[1]);
	print ("mul[2]=%\n", mul[2]);
}
	high0 : u64 = ---;						// 64
	low0 := umul128 (m, mul[0], *high0);	// 0
	high1 : u64 = ---;						// 128
	low1 := umul128 (m, mul[1], *high1);	// 64
	high2 : u64 = ---;						// 192
	low2 := umul128 (m, mul[2], *high2);	// 128
#if DEBUG
{
	print ("high0=%\n", high0);
	print ("low0=%\n", low0);
	print ("high1=%\n", high1);
	print ("low1=%\n", low1);
	print ("high2=%\n", high2);
	print ("low2=%\n", low2);
}
	//s0low := low0;					// 0, unused
	s0high := low1 + high0;				// 64
	c1 := cast (u32) (s0high < low1);
	s1low := low2 + high1 + c1;			// 128
	c2 := cast (u32) (s1low < low2);	// high1 + c1 can't overflow, so compare against low2
	s1high := high2 + c2;				// 192
#if DEBUG
{
	if j < 128 || j > 180
		print ("%\n", j);
}
	ryu_assert (j >= 128);
	ryu_assert (j <= 180);
	if j < 160	// j: [128, 160)
	{
		r0 := cast (u64) mod1e9 (s1high);
		r1 := cast (u64) mod1e9 ((r0 << 32) | (s1low >> 32));
		r2 := cast (u64) ((r1 << 32) | (s1low & 0xffffffff));
		result := mod1e9 (r2 >> (j - 128));
#if DEBUG
{
		print ("j < 160, result=%\n", result);
}
		return result;
	}
	else	// j: [160, 192)
	{
		r0 := cast (u64) mod1e9 (s1high);
		r1 := cast (u64) ((r0 << 32) | (s1low >> 32));
		result := mod1e9 (r1 >> (j - 160));
#if DEBUG
{
		print ("j >= 160, result=%\n", result);
}
		return result;
	}
	return 0;	// Unreachable
}

// Convert `digits` to a sequence of decimal digits. Append the digits to the result.
// The caller has to guarantee that:
//   10^(olength-1) <= digits < 10^olength
// e.g., by passing `olength` as `decimalLength9(digits)`.
append_n_digits :: inline (olength : u32, digits : u32, result : *u8)
{
#if DEBUG
{
	print ("DIGITS=%\n", digits);
}
	i : u32 = 0;
	while digits >= 10000
	{
		c : u32 = digits % 10000;
		digits /= 10000;
		c0 : u32 = (c % 100) << 1;
		c1 : u32 = (c / 100) << 1;
		memcpy (result + olength - i - 2, DIGIT_TABLE.data + c0, 2);
		memcpy (result + olength - i - 4, DIGIT_TABLE.data + c1, 2);
		i += 4;
	}
	if digits >= 100
	{
		c : u32 = (digits % 100) << 1;
		digits /= 100;
		memcpy (result + olength - i - 2, DIGIT_TABLE.data + c, 2);
		i += 2;
	}
	if digits >= 10
	{
		c : u32 = digits << 1;
		memcpy (result + olength - i - 2, DIGIT_TABLE.data + c, 2);
	}
	else
	{
		result[0] = cast (u8) (#char "0" + digits);
	}
}

// Convert `digits` to a sequence of decimal digits. Print the first digit, followed by a decimal
// dot '.' followed by the remaining digits. The caller has to guarantee that:
//   10^(olength-1) <= digits < 10^olength
// e.g., by passing `olength` as `decimalLength9(digits)`.
append_d_digits :: inline (olength : u32, digits : u32, result : *u8)
{
#if DEBUG
{
	print ("DIGITS=%\n", digits);
}
	i : u32 = 0;
	while digits >= 10000
	{
		c : u32 = digits % 10000;
		digits /= 10000;
		c0 : u32 = (c % 100) << 1;
		c1 : u32 = (c / 100) << 1;
		memcpy (result + olength + 1 - i - 2, DIGIT_TABLE.data + c0, 2);
		memcpy (result + olength + 1 - i - 4, DIGIT_TABLE.data + c1, 2);
		i += 4;
	}
	if digits >= 100
	{
		c : u32 = (digits % 100) << 1;
		digits /= 100;
		memcpy (result + olength + 1 - i - 2, DIGIT_TABLE.data + c, 2);
		i += 2;
	}
	if digits >= 10
	{
		c : u32 = digits << 1;
		result[2] = DIGIT_TABLE[c + 1];
		result[1] = #char ".";
		result[0] = DIGIT_TABLE[c];
	}
	else
	{
		result[1] = #char ".";
		result[0] = cast (u8) (#char "0" + digits);
	}
}

// Convert `digits` to decimal and write the last `count` decimal digits to result.
// If `digits` contains additional digits, then those are silently ignored.
append_c_digits :: inline (count : u32, digits : u32, result : *u8)
{
#if DEBUG
{
	print ("DIGITS=%\n", digits);
}
	// Copy pairs of digits from DIGIT_TABLE.
	i : u32 = 0;
	while (i < count - 1)
	{
		c : u32 = (digits % 100) << 1;
		digits /= 100;
		memcpy (result + count - i - 2, DIGIT_TABLE.data + c, 2);
		i += 2;
	}
	// Generate the last digit if count is odd.
	if i < count
		result[count - i - 1] = cast (u8) (#char "0" + (digits % 10));
}

// Convert `digits` to decimal and write the last 9 decimal digits to result.
// If `digits` contains additional digits, then those are silently ignored.
append_nine_digits :: inline (digits : u32, result : *u8)
{
#if DEBUG
{
	print ("DIGITS=%\n", digits);
}
	if digits == 0
	{
		memset (result, #char "0", 9);

		return;
	}
	i : u32 = 0;
	while i < 5
	{
		c : u32 = digits % 10000;
		digits /= 10000;
		c0 : u32 = (c % 100) << 1;
		c1 : u32 = (c / 100) << 1;
		memcpy (result + 7 - i, DIGIT_TABLE.data + c0, 2);
		memcpy (result + 5 - i, DIGIT_TABLE.data + c1, 2);
		i += 4;
	}
	result[0] = cast (u8) (#char "0" + digits);
}

index_for_exponent :: inline (e : u32) -> u32 #must
{
	return (e + 15) / 16;
}

pow10_bits_for_index :: inline (idx : u32) -> u32 #must
{
	return 16 * idx + POW10_ADDITIONAL_BITS;
}

length_for_index :: inline (idx : u32) -> u32 #must
{
	// +1 for ceil, +16 for mantissa, +8 to round up when dividing by 9
	return (log10pow2 (16 * cast (s32) idx) + 1 + 16 + 8) / 9;
}

copy_special_str_printf :: inline (result : *u8, sign : bool, mantissa : u64) -> s32
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
	memcpy (result + index, "Inf".data, "Inf".count);

	return index + cast (s32) "Inf".count;
}

#scope_export

f64_to_fixed_buffered :: (
	f : f64,
	precision : u32,
	result : *u8
) ->
	total_len : s32,
	sign : bool,
	is_inf : bool,
	is_nan : bool,
	integral_part : string,
	fractional_part : string
#no_abc
{
	bits := f64_to_bits (f);
#if DEBUG
{
	print ("IN=");
	for < bit : 63..0
		print ("%", ((bits >> bit) & 1));
	print ("\n");
}
	// Decode bits into sign, mantissa, and exponent.
	ieee_sign := ((bits >> (F64_MANTISSA_BITS + F64_EXPONENT_BITS)) & 1) != 0;
	ieee_mantissa := bits & ((1 << F64_MANTISSA_BITS) - 1);
	ieee_exponent := cast (u32) ((bits >> F64_MANTISSA_BITS) & ((1 << F64_EXPONENT_BITS) - 1));

	// Case distinction; exit early for the easy cases.
	if ieee_exponent == ((1 << F64_EXPONENT_BITS) - 1)
		return copy_special_str_printf (result, ieee_sign, ieee_mantissa), ieee_sign, ieee_mantissa == 0, ieee_mantissa != 0, "", "";
	if ieee_exponent == 0 && ieee_mantissa == 0
	{
		index : s32 = 0;
		if ieee_sign
		{
			result[index] = #char "-";
			index += 1;
		}
		integral_part : string = ---;
		integral_part.data = result + index;
		integral_part.count = 1;
		result[index] = #char "0";
		index += 1;
		fractional_part : string;
		if precision > 0
		{
			result[index] = #char ".";
			index += 1;
			fractional_part.data = result + index;
			fractional_part.count = cast (s64) precision;
			memset (result + index, #char "0", precision);
			index += cast (s32) precision;
		}

		return index, ieee_sign, false, false, integral_part, fractional_part;
	}

	e2 : s32 = ---;
	m2 : u64 = ---;
	if ieee_exponent == 0
	{
		e2 = 1 - F64_BIAS - F64_MANTISSA_BITS;
		m2 = ieee_mantissa;
	}
	else
	{
		e2 = cast (s32) ieee_exponent - F64_BIAS - F64_MANTISSA_BITS;
		m2 = (1 << F64_MANTISSA_BITS) | ieee_mantissa;
	}

#if DEBUG
{
	print ("-> % * 2^%\n", m2, e2);
}

	index : s32 = 0;
	nonzero := false;
	if ieee_sign
	{
		result[index] = #char "-";
		index += 1;
	}
	integral_part : string;
	integral_part.data = result + index;
	if e2 >= -52
	{
		idx := ifx e2 < 0 then 0 else index_for_exponent (cast (u32) e2);
		p10bits := pow10_bits_for_index (idx);
		len := cast (s32) length_for_index (idx);
#if DEBUG
{
	print ("idx=%\n", idx);
	print ("len=%\n", len);
}
		for < i : len - 1..0
		{
			j := cast (u32) (cast (s32) p10bits - e2);
			// Temporary: j is usually around 128, and by shifting a bit, we push it to 128 or above, which is
			// a slightly faster code path in mulShift_mod1e9. Instead, we can just increase the multipliers.
			digits := mul_shift_mod1e9 (m2 << 8, POW10_SPLIT[POW10_OFFSET[idx] + i].data, cast (s32) (j + 8));
			if nonzero
			{
				append_nine_digits (digits, result + index);
				index += 9;
			}
			else if digits != 0
			{
				olength := decimal_length9 (digits);
				append_n_digits (olength, digits, result + index);
				index += cast (s32) olength;
				nonzero = true;
			}
		}
	}
	if !nonzero
	{
		result[index] = #char "0";
		index += 1;
	}
	integral_part.count = (result + index) - integral_part.data;
	if precision > 0
	{
		result[index] = #char ".";
		index += 1;
	}
	fractional_part : string;
	fractional_part.data = result + index;
	fractional_part.count = cast (s64) precision;
#if DEBUG
{
	print ("e2=%\n", e2);
}
	if e2 < 0
	{
		idx := -e2 / 16;
#if DEBUG
{
		print ("idx=%\n", idx);
}
		blocks := precision / 9 + 1;
		// 0 = don't round up; 1 = round up unconditionally; 2 = round up if odd.
		round_up : s32 = 0;
		i : u32 = 0;
		if blocks <= MIN_BLOCK_2[idx]
		{
			i = blocks;
			memset (result + index, #char "0", precision);
			index += cast (s32) precision;
		}
		else if i < MIN_BLOCK_2[idx]
		{
			i = MIN_BLOCK_2[idx];
			memset (result + index, #char "0", 9 * i);
			index += cast (s32) (9 * i);
		}
		while i < blocks
		{
			j := ADDITIONAL_BITS_2 + (-e2 - 16 * idx);
			p := POW10_OFFSET_2[idx] + i - MIN_BLOCK_2[idx];
			if p >= POW10_OFFSET_2[idx + 1]
			{
				// If the remaining digits are all 0, then we might as well use memset.
				// No rounding required in this case.
				fill := precision - 9 * i;
				memset (result + index, #char "0", fill);
				index += cast (s32) fill;

				break;
			}
			// Temporary: j is usually around 128, and by shifting a bit, we push it to 128 or above, which is
			// a slightly faster code path in mulShift_mod1e9. Instead, we can just increase the multipliers.
			digits := mul_shift_mod1e9 (m2 << 8, POW10_SPLIT_2[p].data, j + 8);
#if DEBUG
{
			print ("digits=%\n", digits);
}
			if i < blocks - 1
			{
				append_nine_digits (digits, result + index);
				index += 9;
			}
			else
			{
				maximum := precision - 9 * i;
				last_digit : u32 = 0;
				for k : 0..9 - cast (s32) maximum - 1
				{
					last_digit = digits % 10;
					digits /= 10;
				}
#if DEBUG
{
				print ("last_digit=%\n", last_digit);
}
				if last_digit != 5
				{
					round_up = cast (s32) (last_digit > 5);
				}
				else
				{
					// Is m * 10^(additionalDigits + 1) / 2^(-e2) integer?
					required_twos := -e2 - cast (s32) precision - 1;
					trailing_zeroes := required_twos <= 0 || (required_twos < 60 && multiple_of_power_of_2 (m2, cast (u32) required_twos));
					round_up = cast (s32) (ifx trailing_zeroes then 2 else 1);
#if DEBUG
{
					print ("required_twos=%\n", required_twos);
					print ("trailing_zeroes=%\n", trailing_zeroes);
}
				}
				if maximum > 0
				{
					append_c_digits (maximum, digits, result + index);
					index += cast (s32) maximum;
				}

				break;
			}
			i += 1;
		}
#if DEBUG
{
		print ("round_up=%\n", round_up);
}

		if round_up != 0
		{
			round_index := index;
			dot_index : s32 = 0;	// '.' can't be located at index 0
			while true
			{
				round_index -= 1;
				if round_index == -1 || result[round_index] == #char "-"
				{
					result[round_index + 1] = #char "1";
					if dot_index > 0
					{
						result[dot_index] = #char "0";
						result[dot_index + 1] = #char ".";
						integral_part.count += 1;
						fractional_part.data += 1;
					}
					result[index] = #char "0";
					index += 1;

					break;
				}
				c := result[round_index];
				if c == #char "."
				{
					dot_index = round_index;

					continue;
				}
				else if c == #char "9"
				{
					result[round_index] = #char "0";
					round_up = 1;

					continue;
				}
				else
				{
					if round_up == 2 && (c % 2) == 0
						break;
					result[round_index] = c + 1;

					break;
				}
			}
		}
	}
	else
	{
		memset (result + index, #char "0", precision);
		index += cast (s32) precision;
	}
	
	return index, ieee_sign, false, false, integral_part, fractional_part;
}

f64_to_fixed :: inline (
	f : f64,
	precision : u32,
	allocator : Allocator
) ->
	string #must,
	sign : bool,
	is_inf : bool,
	is_nan : bool,
	integral_part : string,
	fractional_part : string
{
	result : string = ---;
	result.data = allocator.proc (.ALLOCATE, 350 + cast (s64) precision, 0, null, allocator.data);
	length, sign, is_inf, is_nan, integral_part, fractional_part := f64_to_fixed_buffered (f, precision, result.data);
	result.count = length;

	return result, sign, is_inf, is_nan, integral_part, fractional_part;
}

f64_to_exp_buffered :: (
	f : f64,
	precision : u32,
	result : *u8
) ->
	total_len : s32,
	sign : bool,
	is_inf : bool,
	is_nan : bool,
	integral_part : string,
	fractional_part : string,
	exponent_sign : bool,
	exponent_part : string
#no_abc
{
	bits := f64_to_bits (f);
#if DEBUG
{
	print ("IN=");
	for < bit : 63..0
		print ("%", (bits >> bit) & 0x1);
	print ("\n");
}

	// Decode bits into sign, mantissa, and exponent.
	ieee_sign := ((bits >> (F64_MANTISSA_BITS + F64_EXPONENT_BITS)) & 1) != 0;
	ieee_mantissa := bits & ((1 << F64_MANTISSA_BITS) - 1);
	ieee_exponent := cast (u32) ((bits >> F64_MANTISSA_BITS) & ((1 << F64_EXPONENT_BITS) - 1));

	// Case distinction; exit early for the easy cases.
	if ieee_exponent == ((1 << F64_EXPONENT_BITS) - 1)
		return copy_special_str_printf (result, ieee_sign, ieee_mantissa), ieee_sign, ieee_mantissa == 0, ieee_mantissa != 0, "", "", false, "";
	if ieee_exponent == 0 && ieee_mantissa == 0
	{
		index : s32 = 0;
		if ieee_sign
		{
			result[index] = #char "-";
			index += 1;
		}
		integral_part : string = ---;
		integral_part.data = result + index;
		integral_part.count = 1;
		result[index] = #char "0";
		index += 1;
		fractional_part : string;
		if precision > 0
		{
			result[index] = #char ".";
			index += 1;
			fractional_part.data = result + index;
			fractional_part.count = cast (s32) precision;
			memset (result + index, #char "0", precision);
			index += cast (s32) precision;
		}
		exponent_part : string = ---;
		exponent_part.data = result + index + 2;
		exponent_part.count = 2;
		memcpy (result + index, "e+00".data, 4);
		index += 4;

		return index, ieee_sign, false, false, integral_part, fractional_part, false, exponent_part;
	}

	e2 : s32 = ---;
	m2 : u64 = ---;
	if ieee_exponent == 0
	{
		e2 = 1 - F64_BIAS - F64_MANTISSA_BITS;
		m2 = ieee_mantissa;
	}
	else
	{
		e2 = cast (s32) ieee_exponent - F64_BIAS - F64_MANTISSA_BITS;
		m2 = (1 << F64_MANTISSA_BITS) | ieee_mantissa;
	}

#if DEBUG
{
	print ("-> % * 2^%\n", m2, e2);
}

	print_decimal_point := precision > 0;
	prec := precision + 1;
	index : s32 = 0;
	if ieee_sign
	{
		result[index] = #char "-";
		index += 1;
	}
	digits : u32 = 0;
	printed_digits : u32 = 0;
	available_digits : u32 = 0;
	exp : s32 = 0;
	integral_part : string = ---;
	integral_part.data = result + index;
	integral_part.count = 1;
	if e2 >= -52
	{
		idx := ifx e2 < 0 then 0 else index_for_exponent (cast (u32) e2);
		p10bits := pow10_bits_for_index (idx);
		len := cast (s32) length_for_index (idx);
#if DEBUG
{
		print ("idx=%\n", idx);
		print ("len=%\n", len);
}
		for < i : len - 1..cast (s32) 0
		{
			j := cast (u32) (cast (s32) p10bits - e2);
			// Temporary: j is usually around 128, and by shifting a bit, we push it to 128 or above, which is
			// a slightly faster code path in mulShift_mod1e9. Instead, we can just increase the multipliers.
			digits = mul_shift_mod1e9 (m2 << 8, POW10_SPLIT[POW10_OFFSET[idx] + i].data, cast (s32) (j + 8));
			if printed_digits != 0
			{
				if printed_digits + 9 > prec
				{
					available_digits = 9;

					break;
				}
				append_nine_digits (digits, result + index);
				index += 9;
				printed_digits += 9;
			}
			else if digits != 0
			{
				available_digits = decimal_length9 (digits);
				exp = i * 9 + cast (s32) available_digits - 1;
				if available_digits > precision
					break;
				if print_decimal_point
				{
					append_d_digits (available_digits, digits, result + index);
					index += cast (s32) available_digits + 1;	// +1 for decimal point
				}
				else
				{
					result[index] = cast (u8) (#char "0" + digits);
					index += 1;
				}
				printed_digits = available_digits;
				available_digits = 0;
			}
		}
	}

	if e2 < 0 && available_digits == 0
	{
		idx := -e2 / 16;
#if DEBUG
		print ("idx=%, e2=%, min=%\n", idx, e2, MIN_BLOCK_2[idx]);
		for i : MIN_BLOCK_2[idx]..cast (s32) 199
		{
			j := ADDITIONAL_BITS_2 + (-e2 - 16 * idx);
			p := POW10_OFFSET_2[idx] + cast (u32) i - MIN_BLOCK_2[idx];
			// Temporary: j is usually around 128, and by shifting a bit, we push it to 128 or above, which is
			// a slightly faster code path in mulShift_mod1e9. Instead, we can just increase the multipliers.
			digits = ifx p >= POW10_OFFSET_2[idx + 1] then 0 else mul_shift_mod1e9 (m2 << 8, POW10_SPLIT_2[p].data, j + 8);
#if DEBUG
{
			print ("exact=% * (% + % << 64) >> %\n", m2, POW10_SPLIT_2[p][0], POW10_SPLIT_2[p][1], j);
			print ("digits=%\n", digits);
}
			if printed_digits != 0
			{
				if printed_digits + 9 > prec
				{
					available_digits = 9;

					break;
				}
				append_nine_digits (digits, result + index);
				index += 9;
				printed_digits += 9;
			}
			else if digits != 0
			{
				available_digits = decimal_length9 (digits);
				exp = -(i + 1) * 9 + cast (s32) available_digits - 1;
				if available_digits > prec
					break;
				if print_decimal_point
				{
					append_d_digits (available_digits, digits, result + index);
					index += cast (s32) available_digits + 1;	// +1 for decimal point
				}
				else
				{
					result[index] = cast (u8) (#char "0" + digits);
					index += 1;
				}
				printed_digits = available_digits;
				available_digits = 0;
			}
		}
	}

	maximum := prec - printed_digits;
#if DEBUG
{
	print ("available_digits=%\n", available_digits);
	print ("digits=%\n", digits);
	print ("maximum=%\n", maximum);
}
	if available_digits == 0
		digits = 0;
	last_digit : u32 = 0;
	if available_digits > maximum
	{
		for k : 0..available_digits - maximum - 1
		{
			last_digit = digits % 10;
			digits /= 10;
		}
	}
#if DEBUG
	print ("last_digit=%\n", last_digit);
	// 0 = don't round up; 1 = round up unconditionally; 2 = round up if odd.
	round_up : s32 = 0;
	if last_digit != 5
		round_up = cast (s32) (last_digit > 5);
	else
	{
		// Is m * 2^e2 * 10^(precision + 1 - exp) integer?
		// precision was already increased by 1, so we don't need to write + 1 here.
		rexp := cast (s32) prec - exp;
		required_twos := -e2 - rexp;
		trailing_zeroes := required_twos <= 0
			|| (required_twos < 60 && multiple_of_power_of_2 (m2, cast (u32) required_twos));
		if rexp < 0
		{
			required_fives := -rexp;
			trailing_zeroes = trailing_zeroes && multiple_of_power_of_5 (m2, cast (u32) required_fives);
		}
		round_up = cast (s32) (ifx trailing_zeroes then 2 else 1);
#if DEBUG
{
		print ("required_twos=%\n", required_twos);
		print ("trailing_zeroes=%\n", trailing_zeroes);
}
	}
	if printed_digits != 0
	{
		if digits == 0
			memset (result + index, #char "0", maximum);
		else
			append_c_digits (maximum, digits, result + index);
		index += cast (s32) maximum;
	}
	else
	{
		if print_decimal_point
		{
			append_d_digits (maximum, digits, result + index);
			index += cast (s32) maximum + 1;	// +1 for decimal point
		}
		else
		{
			result[index] = cast (u8) (#char "0" + digits);
			index += 1;
		}
	}
#if DEBUG
	print ("round_up=%\n", round_up);

	if round_up != 0
	{
		round_index := index;
		while true
		{
			round_index -= 1;
			c := result[round_index];
			if round_index == -1 || c == #char "-"
			{
				result[round_index + 1] = #char "1";
				exp += 1;

				break;
			}
			if c == #char "."
				continue;
			else if c == #char "9"
			{
				result[round_index] = #char "0";
				round_up = 1;

				continue;
			}
			else
			{
				if round_up == 2 && (c % 2) == 0
					break;
				result[round_index] = c + 1;

				break;
			}
		}
	}
	result[index] = #char "e";
	index += 1;
	if exp < 0
	{
		result[index] = #char "-";
		index += 1;
		exp = -exp;
	}
	else
	{
		result[index] = #char "+";
		index += 1;
	}

	fractional_part : string;
	if precision > 0
	{
		fractional_part.data = integral_part.data + 2;
		fractional_part.count = precision;
	}
	exponent_part : string = ---;
	exponent_part.data = result + index;
	if exp >= 100
	{
		c := exp % 10;
		memcpy (result + index, DIGIT_TABLE.data + 2 * (exp / 10), 2);
		result[index + 2] = cast (u8) (#char "0" + c);
		index += 3;
		exponent_part.count = 3;
	}
	else
	{
		memcpy (result + index, DIGIT_TABLE.data + 2 * exp, 2);
		index += 2;
		exponent_part.count = 2;
	}

	return index, ieee_sign, false, false, integral_part, fractional_part, exp < 0, exponent_part;
}

f64_to_exp :: inline (
	f : f64,
	precision : u32,
	allocator : Allocator
) ->
	string #must,
	sign : bool,
	is_inf : bool,
	is_nan : bool,
	integral_part : string,
	fractional_part : string,
	exponent_sign : bool,
	exponent_part : string
{
	result : string = ---;
	result.data = allocator.proc (.ALLOCATE, 7 + cast (s64) precision, 0, null, allocator.data);
	length, sign, is_inf, is_nan, integral_part, fractional_part, exponent_sign, exponent_part := f64_to_exp_buffered (f, precision, result.data);
	result.count = length;

	return result, sign, is_inf, is_nan, integral_part, fractional_part, exponent_sign, exponent_part;
}
