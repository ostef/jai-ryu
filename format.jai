Format :: struct
{
	Flags :: enum_flags
	{
		FORCE_SIGN :: 0x01;
		ALIGN_SIGN :: 0x02;
		FORCE_SIGN_ON_EXPONENT :: 0x04;
		UPPERCASE  :: 0x08;
	}

	flags : Flags;
	min_width : u32;
	precision : u32;
	decimal_separator : u8 = #char ".";
	nan_string := "NaN";
	inf_string := "Inf";
}

f64_to_fixed_buffered :: inline (f : f64, using fmt : Format, result : *u8) -> s32
{
	buff : [500]u8;
	total_len, sign, is_inf, is_nan, integral_part, fractional_part := f64_to_fixed_buffered (f, precision, buff.data);
	index : s32 = 0;
	if is_nan
	{
		fill_width := cast (s32) min_width - cast (s32) nan_string.count;
		if fill_width > 0
		{
			memset (result, #char " ", fill_width);
			index += fill_width;
		}
		memcpy (result + index, nan_string.data, nan_string.count);

		return index + cast (s32) nan_string.count;
	}
	if is_inf
	{
		lead_with_sign := sign || (flags & .FORCE_SIGN) != 0 || (flags & .ALIGN_SIGN != 0);
		fill_width := cast (s32) min_width - cast (s32) lead_with_sign - cast (s32) inf_string.count;
		if fill_width > 0
		{
			memset (result, #char " ", fill_width);
			index += fill_width;
		}
	}
	if sign
	{
		result[index] = #char "-";
		index += 1;
	}
	else if flags & .FORCE_SIGN
	{
		result[index] = #char "+";
		index += 1;
	}
	else if flags & .ALIGN_SIGN
	{
		result[index] = #char " ";
		index += 1;
	}
	if is_inf
	{
		memcpy (result + index, inf_string.data, inf_string.count);

		return index + cast (s32) inf_string.count;
	}
	fill_width := cast (s32) min_width
		- index
		- cast (s32) integral_part.count
		- cast (s32) (precision > 0)
		- cast (s32) fractional_part.count;
	if fill_width > 0
	{
		memset (result + index, #char "0", fill_width);
		index += fill_width;
	}
	memcpy (result + index, integral_part.data, integral_part.count);
	index += cast (s32) integral_part.count;
	if precision > 0
	{
		result[index] = decimal_separator;
		index += 1;
		memcpy (result + index, fractional_part.data, fractional_part.count);
		index += cast (s32) fractional_part.count;
	}

	return index;
}

f64_to_exp_buffered :: inline (f : f64, using fmt : Format, result : *u8) -> s32
{
	buff : [500]u8;
	total_len, sign, is_inf, is_nan, integral_part, fractional_part, exponent_sign, exponent_part := f64_to_exp_buffered (f, precision, buff.data);
	index : s32 = 0;
	if is_nan
	{
		fill_width := cast (s32) min_width - cast (s32) nan_string.count;
		if fill_width > 0
		{
			memset (result, #char " ", fill_width);
			index += fill_width;
		}
		memcpy (result + index, nan_string.data, nan_string.count);

		return index + cast (s32) nan_string.count;
	}
	if is_inf
	{
		lead_with_sign := sign || (flags & .FORCE_SIGN) != 0 || (flags & .ALIGN_SIGN != 0);
		fill_width := cast (s32) min_width - cast (s32) lead_with_sign - cast (s32) inf_string.count;
		if fill_width > 0
		{
			memset (result, #char " ", fill_width);
			index += fill_width;
		}
	}
	if sign
	{
		result[index] = #char "-";
		index += 1;
	}
	else if flags & .FORCE_SIGN
	{
		result[index] = #char "+";
		index += 1;
	}
	else if flags & .ALIGN_SIGN
	{
		result[index] = #char " ";
		index += 1;
	}
	if is_inf
	{
		memcpy (result + index, inf_string.data, inf_string.count);

		return index + cast (s32) inf_string.count;
	}
	lead_exponent_with_sign := exponent_sign || (flags & .FORCE_SIGN_ON_EXPONENT) != 0;
	fill_width := cast (s32) min_width
		- index
		- cast (s32) integral_part.count
		- cast (s32) (precision > 0)
		- cast (s32) fractional_part.count
		- 1
		- cast (s32) lead_exponent_with_sign
		- cast (s32) exponent_part.count;
	if fill_width > 0
	{
		memset (result + index, #char "0", fill_width);
		index += fill_width;
	}
	memcpy (result + index, integral_part.data, integral_part.count);
	index += cast (s32) integral_part.count;
	if precision > 0
	{
		result[index] = decimal_separator;
		index += 1;
		memcpy (result + index, fractional_part.data, fractional_part.count);
		index += cast (s32) fractional_part.count;
	}
	if flags & .UPPERCASE
		result[index] = #char "E";
	else
		result[index] = #char "e";
	index += 1;
	if exponent_sign
	{
		result[index] = #char "-";
		index += 1;
	}
	else if flags & .FORCE_SIGN_ON_EXPONENT
	{
		result[index] = #char "+";
		index += 1;
	}
	memcpy (result + index, exponent_part.data, exponent_part.count);
	index += cast (s32) exponent_part.count;

	return index;
}
