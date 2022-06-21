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

#module_parameters (DEBUG := false)
(
	// Use #asm instructions, mainly for umul128. There shouldn't be any reason
	// to set this to false, since Jai only supports x64 so this should always
	// be available, and faster.
	USE_64BIT_INSTRUCTIONS := true,
	// Use small tables instead of full tables for f64_to_shortest.
	// Not entirely supported since string_to_f64 only implements it partially.
	// If you want small tables then don't import string to float.
	// Removes about 5 KB to the final executable.
	OPTIMIZE_SIZE := false,
	IMPORT_FLOAT_TO_SHORTEST := true,
	IMPORT_FLOAT_TO_FIXED_AND_EXP := true,
	IMPORT_STRING_TO_FLOAT := true
);

#assert IMPORT_FLOAT_TO_SHORTEST || IMPORT_FLOAT_TO_FIXED_AND_EXP || IMPORT_STRING_TO_FLOAT
	"Nothing useful will get imported. At least one of IMPORT_FLOAT_TO_SHORTEST, IMPORT_FLOAT_TO_FIXED_AND_EXP and IMPORT_STRING_TO_FLOAT must be set in the program parameters.";

#scope_module

#if DEBUG
{
	Basic :: #import "Basic";	// For print
	print :: Basic.print;
}

#scope_export

#load "common.jai";
#load "digit_table.jai";

Parse_Status :: enum
{
	SUCCESS :: 0;
	INPUT_TOO_SHORT :: 1;
	INPUT_TOO_LONG  :: 2;
	MALFORMED_INPUT :: 3;
	NOT_IMPLEMENTED :: 4;
}

Format :: struct
{
	Flags :: enum_flags
	{
		FORCE_SIGN :: 0x01;
		ALIGN_SIGN :: 0x02;
		FORCE_SIGN_ON_EXPONENT :: 0x04;
		UPPERCASE  :: 0x08;
		REMOVE_TRAILING_ZEROES :: 0x10;
	}

	flags : Flags;
	min_width : u32;
	precision : u32;
	decimal_separator : u8 = #char ".";
	nan_string := "NaN";
	inf_string := "Inf";
}

f32 :: float32;
f64 :: float64;

// A floating decimal representing m * 10^e.
F32_Decimal :: struct
{
	mantissa : u32;
	// Decimal exponent's range is -45 to 38
	// inclusive, and can fit in a short if needed.
	exponent : s32;
}

// A floating decimal representing m * 10^e.
F64_Decimal :: struct
{
	mantissa : u64;
	// Decimal exponent's range is -324 to 308
	// inclusive, and can fit in a short if needed.
	exponent : s32;
}

#if IMPORT_FLOAT_TO_SHORTEST || IMPORT_STRING_TO_FLOAT
{
	#load "f32_intrinsics.jai";
	#load "f32_full_table.jai";
}

#if IMPORT_FLOAT_TO_SHORTEST
	#load "f32_to_shortest.jai";
else
{
	f32_to_decimal :: inline (ieee_mantissa : u32, ieee_exponent : u32) -> F32_Decimal #must
	#no_context { #assert false "Float to shortest not imported. See the program parameters of this module."; return .{}; }

	f32_to_shortest_buffered :: (f : f32, result : *u8) -> s32
	#no_context { #assert false "Float to shortest not imported. See the program parameters of this module."; return 0; }
	
	f32_to_shortest :: inline (f : f32, allocator : Allocator) -> string #must
	{ #assert false "Float to shortest not imported. See the program parameters of this module."; return ""; }
}

#load "f64_intrinsics.jai";
#if IMPORT_FLOAT_TO_SHORTEST || IMPORT_STRING_TO_FLOAT
{
	#if OPTIMIZE_SIZE
		#load "f64_small_table.jai";
	else
		#load "f64_full_table.jai";
}

#if IMPORT_FLOAT_TO_SHORTEST
	#load "f64_to_shortest.jai";
else
{
	f64_to_decimal :: inline (ieee_mantissa : u64, ieee_exponent : u32) -> F64_Decimal
	#no_context { #assert false "Float to shortest not imported. See the program parameters of this module."; return .{}; }

	f64_to_shortest_buffered :: (f : f64, result : *u8) -> s32
	#no_context { #assert false "Float to shortest not imported. See the program parameters of this module."; return 0; }

	f64_to_shortest :: inline (f : f64, allocator : Allocator) -> string #must
	{ #assert false "Float to shortest not imported. See the program parameters of this module."; return ""; }
}

#if IMPORT_FLOAT_TO_FIXED_AND_EXP
{
	#load "f64_to_fixed_full_table.jai";
	#load "f64_to_fixed.jai";
	#load "format.jai";
}
else
{
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
	#no_context { #assert false "Float to fixed and exp not imported. See the program parameters of this module."; return 0, false, false, false, "", ""; }

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
	{ #assert false "Float to fixed and exp not imported. See the program parameters of this module."; return "", false, false, false, "", ""; }
	
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
	#no_context { #assert false "Float to fixed and exp not imported. See the program parameters of this module."; return 0, false, false, false, "", "", false, ""; }

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
	{ #assert false "Float to fixed and exp not imported. See the program parameters of this module."; return "", false, false, false, "", "", false, ""; }
	
	f64_to_fixed_buffered :: inline (f : f64, using fmt : Format, result : *u8, $temp_buffer_size := 500) -> s32
	#no_context { #assert false "Float to fixed and exp not imported. See the program parameters of this module."; return 0; }

	f64_to_exp_buffered :: inline (f : f64, using fmt : Format, result : *u8, $temp_buffer_size := 50) -> s32
	#no_context { #assert false "Float to fixed and exp not imported. See the program parameters of this module."; return 0; }

	f64_format :: inline (
		result : *u8,
		using fmt : Format,
		sign : bool,
		is_inf : bool,
		is_nan : bool,
		integral_part : string,
		fractional_part : string,
		exponent_sign : bool,
		exponent_part : string
	) -> s32
	#no_context { #assert false "Float to fixed and exp not imported. See the program parameters of this module."; return 0; }
}

#if IMPORT_STRING_TO_FLOAT
{
	#load "string_to_f32.jai";
	#load "string_to_f64.jai";
}
else
{
	string_to_f32 :: (buffer : *u8, len : s32, using fmt := Format.{}) -> value : f32, status : Parse_Status, bytes_read : s32
	#no_context { #assert false "String to float conversion is not imported. See the program parameters of this module."; return 0, .NOT_IMPLEMENTED, 0; }

	string_to_f32 :: inline (str : string, using fmt := Format.{}) -> value : f32, status : Parse_Status, bytes_read : s32
	#no_context { #assert false "String to float conversion is not imported. See the program parameters of this module."; return 0, .NOT_IMPLEMENTED, 0; }

	string_to_f64 :: (buffer : *u8, len : s32, using fmt := Format.{}) -> value : f64, status : Parse_Status, bytes_read : s32
	#no_context { #assert false "String to float conversion is not imported. See the program parameters of this module."; return 0, .NOT_IMPLEMENTED, 0; }

	string_to_f64 :: inline (str : string, using fmt := Format.{}) -> value : f64, status : Parse_Status, bytes_read : s32
	#no_context { #assert false "String to float conversion is not imported. See the program parameters of this module."; return 0, .NOT_IMPLEMENTED, 0; }
}

#scope_module
