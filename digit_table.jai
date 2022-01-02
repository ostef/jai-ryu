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

// A table of all two-digit numbers. This is used to speed up decimal digit
// generation by copying pairs of digits into the final output.
DIGIT_TABLE :: #insert -> string
{
	result : [203]u8;
	result[0] = #char "\"";
	for i : 0..9
	{
		for j : 0..9
		{
			result[1 + i * 20 + j * 2] = cast (u8) (#char "0" + i);
			result[1 + i * 20 + j * 2 + 1] = cast (u8) (#char "0" + j);
		}
	}
	result[201] = #char "\"";
	result[202] = #char ";";
	str : string = ---;
	str.data  = result.data;
	str.count = result.count;

	return str;
}
