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

#module_parameters (
	// Use #asm instructions, mainly for umul128. There shouldn't be any reason
	// to set this to false, since Jai only supports x64 so this should always
	// be available, and faster.
	USE_64BIT_INSTRUCTIONS := true,
	// Use small tables instead of full tables for f64_to_shortest.
	// Not entirely supported since string_to_f64 only implements it partially.
	// If you want small tables then don't import string to float.
	OPTIMIZE_SIZE := false,	// OPTIMIZE_SIZE = false adds about 5 KB to the final executable.
	IMPORT_FLOAT_TO_SHORTEST := true,
	IMPORT_FLOAT_TO_FIXED_AND_EXP := true,
	IMPORT_STRING_TO_FLOAT := true,
	DEBUG := false
);

#assert IMPORT_FLOAT_TO_SHORTEST || IMPORT_FLOAT_TO_FIXED_AND_EXP || IMPORT_STRING_TO_FLOAT
	"Nothing useful will get imported. At least one of IMPORT_FLOAT_TO_SHORTEST, IMPORT_FLOAT_TO_FIXED_AND_EXP and IMPORT_STRING_TO_FLOAT must be set in the module parameters.";

#scope_module

#if DEBUG
{
	Basic :: #import "Basic";	// For print
	print :: Basic.print;
}

#scope_export

#load "common.jai";
#load "digit_table.jai";

#if IMPORT_FLOAT_TO_SHORTEST || IMPORT_STRING_TO_FLOAT
{
	#load "f32_intrinsics.jai";
	#load "f32_full_table.jai";
}
#if IMPORT_FLOAT_TO_SHORTEST
	#load "f32_to_shortest.jai";

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
#if IMPORT_FLOAT_TO_FIXED_AND_EXP
{
	#load "f64_to_fixed_full_table.jai";
	#load "f64_to_fixed.jai";
	#load "format.jai";
}

#if IMPORT_STRING_TO_FLOAT
{
	#load "string_to_f32.jai";
	#load "string_to_f64.jai";
}

#if IMPORT_STRING_TO_FLOAT
{

Parse_Status :: enum
{
	SUCCESS :: 0;
	INPUT_TOO_SHORT :: 1;
	INPUT_TOO_LONG  :: 2;
	MALFORMED_INPUT :: 3;
}

}

#scope_module

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
