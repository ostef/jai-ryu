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

F64_POW5_INV_BITCOUNT :: 125;
F64_POW5_BITCOUNT :: 125;

#scope_file

F64_POW5_INV_SPLIT2 : [15][2]u64 : .[
	.[                    1, 2305843009213693952 ],
	.[  5955668970331000884, 1784059615882449851 ],
	.[  8982663654677661702, 1380349269358112757 ],
	.[  7286864317269821294, 2135987035920910082 ],
	.[  7005857020398200553, 1652639921975621497 ],
	.[ 17965325103354776697, 1278668206209430417 ],
	.[  8928596168509315048, 1978643211784836272 ],
	.[ 10075671573058298858, 1530901034580419511 ],
	.[   597001226353042382, 1184477304306571148 ],
	.[  1527430471115325346, 1832889850782397517 ],
	.[ 12533209867169019542, 1418129833677084982 ],
	.[  5577825024675947042, 2194449627517475473 ],
	.[ 11006974540203867551, 1697873161311732311 ],
	.[ 10313493231639821582, 1313665730009899186 ],
	.[ 12701016819766672773, 2032799256770390445 ]
];
POW5_INV_OFFSETS : [19]u32 : .[
	0x54544554, 0x04055545, 0x10041000, 0x00400414, 0x40010000, 0x41155555,
	0x00000454, 0x00010044, 0x40000000, 0x44000041, 0x50454450, 0x55550054,
	0x51655554, 0x40004000, 0x01000001, 0x00010500, 0x51515411, 0x05555554,
	0x00000000
];

F64_POW5_SPLIT2 : [13][2]u64 : .[
	.[                    0, 1152921504606846976 ],
	.[                    0, 1490116119384765625 ],
	.[  1032610780636961552, 1925929944387235853 ],
	.[  7910200175544436838, 1244603055572228341 ],
	.[ 16941905809032713930, 1608611746708759036 ],
	.[ 13024893955298202172, 2079081953128979843 ],
	.[  6607496772837067824, 1343575221513417750 ],
	.[ 17332926989895652603, 1736530273035216783 ],
	.[ 13037379183483547984, 2244412773384604712 ],
	.[  1605989338741628675, 1450417759929778918 ],
	.[  9630225068416591280, 1874621017369538693 ],
	.[   665883850346957067, 1211445438634777304 ],
	.[ 14931890668723713708, 1565756531257009982 ]
];
POW5_OFFSETS : [21]u32 : .[
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x40000000, 0x59695995,
	0x55545555, 0x56555515, 0x41150504, 0x40555410, 0x44555145, 0x44504540,
	0x45555550, 0x40004000, 0x96440440, 0x55565565, 0x54454045, 0x40154151,
	0x55559155, 0x51405555, 0x00000105
];

#scope_module

F64_POW5_TABLE_SIZE :: 26;

F64_POW5_TABLE : [F64_POW5_TABLE_SIZE]u64 : .[
	1, 5, 25, 125, 625, 3125, 15625, 78125, 390625,
	1953125, 9765625, 48828125, 244140625, 1220703125, 6103515625,
	30517578125, 152587890625, 762939453125, 3814697265625,
	19073486328125, 95367431640625, 476837158203125,
	2384185791015625, 11920928955078125, 59604644775390625,
	298023223876953125 //, 1490116119384765625
];

// Computes 5^i in the form required by Ryu, and stores it in the given pointer.
f64_compute_pow5 :: inline (i : u32, result : *u64)
#no_context
{
	base : u32 = i / F64_POW5_TABLE_SIZE;
	base2 : u32 = base * F64_POW5_TABLE_SIZE;
	offset : u32 = i - base2;
	mul := F64_POW5_SPLIT2[base];
	if offset == 0
	{
		result[0] = mul[0];
		result[1] = mul[1];

		return;
	}
	m := F64_POW5_TABLE[offset];
	high1 : u64 = ---;
	low1 := umul128 (m, mul[1], *high1);
	high0 : u64 = ---;
	low0 := umul128 (m, mul[0], *high0);
	sum := high0 + low1;
	if sum < high0
		high1 += 1;	// overflow into high1
	// high1 | sum | low0
	delta := cast (u32) (pow5bits (cast (s32) i) - pow5bits (cast (s32) base2));
	result[0] = shiftright128 (low0, sum, delta) + ((POW5_OFFSETS[i / 16] >> ((i % 16) << 1)) & 3);
	result[1] = shiftright128 (sum, high1, delta);
}

// Computes 5^-i in the form required by Ryu, and stores it in the given pointer.
f64_compute_inv_pow5 :: inline (i : u32, result : *u64)
#no_context
{
	base := (i + F64_POW5_TABLE_SIZE - 1) / F64_POW5_TABLE_SIZE;
	base2 := base * F64_POW5_TABLE_SIZE;
	offset := base2 - i;
	mul := F64_POW5_INV_SPLIT2[base];	// 1/5^base2
	if offset == 0
	{
		result[0] = mul[0];
		result[1] = mul[1];

		return;
	}
	m := F64_POW5_TABLE[offset];
	high1 : u64 = ---;
	low1 := umul128 (m, mul[1], *high1);
	high0 : u64 = ---;
	low0 := umul128 (m, mul[0], *high0);
	sum := high0 + low1;
	if sum < high0
		high1 += 1;	// overflow into high1
	// high1 | sum | low0
	delta := cast (u32) (pow5bits (cast (s32) base2) - pow5bits (cast (s32) i));
	result[0] = shiftright128 (low0, sum, delta) + 1 + ((POW5_INV_OFFSETS[i / 16] >> ((i % 16) << 1)) & 3);
	result[1] = shiftright128 (sum, high1, delta);
}
