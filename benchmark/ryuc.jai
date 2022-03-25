Status :: enum s32
{
	SUCCESS;
	INPUT_TOO_SHORT;
	INPUT_TOO_LONG;
	MALFORMED_INPUT;
}

s2d_n :: (buffer : *u8, len : s32, res : *f64) -> Status #foreign ryuc;
s2d :: (buffer : *u8, res : *f64) -> Status #foreign ryuc;

s2f_n :: (buffer : *u8, len : s32, res : *f32) -> Status #foreign ryuc;
s2f :: (buffer : *u8, res : *f32) -> Status #foreign ryuc;

d2fixed_buffered_n :: (d : f64, precision : u32, result : *u8) -> s32 #foreign ryuc;
d2exp_buffered_n :: (d : f64, precision : u32, result : *u8) -> s32 #foreign ryuc;

#scope_file

#if OS == .WINDOWS
	ryuc :: #foreign_library, no_dll "lib/ryu_win";
else
	ryuc :: #foreign_library, no_dll "lib/ryu_linux";
