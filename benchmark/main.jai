#import "Basic";
#import "Math";
#import "Random";
#import "File";
ryu :: #import "Ryu" () (USE_64BIT_INSTRUCTIONS = true, OPTIMIZE_SIZE = false);
#import "stb_sprintf";

#load "ryuc.jai";

//F64_POSITIVE_INFINITY :: 0h7ff0_0000_0000_0000;
//F64_NEGATIVE_INFINITY :: 0hfff0_0000_0000_0000;

f32 :: float32;
f64 :: float64;

BUFFER_SIZE :: 5000;
PRECISIONS :: u32.[ 0, 3, 6, 10, 16, 100, 500 ];
BENCH_COUNT :: PRECISIONS.count;

Benchmark_Data :: struct
{
	n : s64;
	min : f64;
	max : f64;
	mean : f64;
}

update :: inline (using data : *Benchmark_Data, x : f64)
{
	if x < min then min = x;
	if x > max then max = x;
	n += 1;
	d := x - mean;
	mean += d / n;
}

generate_double :: inline () -> f64
{
	low := random_get ();
	hi  := random_get ();
	r := ((cast (u64) hi) << 32 | low);

	return <<(cast (*f64) *r);
}

benchmark :: (
	samples : u32,
	iterations : u32,
	out_ryufmt : *[BENCH_COUNT]Benchmark_Data,
	out_ryuc : *[BENCH_COUNT]Benchmark_Data,
	out_stbsp : *[BENCH_COUNT]Benchmark_Data,
	$fixed : bool)
{
	fmt : [100]u8 = ---;
	ryufmt_buffer : [BUFFER_SIZE]u8 = ---;
	ryuc_buffer   : [BUFFER_SIZE]u8 = ---;
	stbsp_buffer  : [BUFFER_SIZE]u8 = ---;

	for precision : PRECISIONS
	{
#if fixed
		stbsp_snprintf (fmt.data, fmt.count, "%%.%df", precision);
else
		stbsp_snprintf (fmt.data, fmt.count, "%%.%de", precision);

		ryufmt_data := *(<<out_ryufmt)[it_index];
		ryufmt_data.n = 0;
		ryufmt_data.mean = 0;
		ryufmt_data.min = F64_POSITIVE_INFINITY;
		ryufmt_data.max = F64_NEGATIVE_INFINITY;
		ryuc_data := *(<<out_ryuc)[it_index];
		ryuc_data.n = 0;
		ryuc_data.mean = 0;
		ryuc_data.min = F64_POSITIVE_INFINITY;
		ryuc_data.max = F64_NEGATIVE_INFINITY;
		stbsp_data := *(<<out_stbsp)[it_index];
		stbsp_data.n = 0;
		stbsp_data.mean = 0;
		stbsp_data.min = F64_POSITIVE_INFINITY;
		stbsp_data.max = F64_NEGATIVE_INFINITY;

		ryu_fmt : ryu.Format;
		ryu_fmt.precision = precision;
		ryu_fmt.flags |= .REMOVE_TRAILING_ZEROES;
		for i : 0..samples - 1
		{
			f := generate_double ();
			t1 := get_time ();
			for j : 0..iterations - 1
#if fixed
				ryu.f64_to_fixed_buffered (f, precision, ryufmt_buffer.data);
else
				ryu.f64_to_exp_buffered (f, precision, ryufmt_buffer.data);
			t2 := get_time ();
			delta := ((t2 - t1) * 1000000000.0) / cast (f64) iterations;
			update (ryufmt_data, delta);

			t1 = get_time ();
			for j : 0..iterations - 1
#if fixed
				d2fixed_buffered_n (f, precision, ryufmt_buffer.data);
else
				d2exp_buffered_n (f, precision, ryufmt_buffer.data);
			t2 = get_time ();
			delta = ((t2 - t1) * 1000000000.0) / cast (f64) iterations;
			update (ryuc_data, delta);

			t1 = get_time ();
			for j : 0..iterations - 1
				stbsp_snprintf (stbsp_buffer.data, stbsp_buffer.count, fmt.data, f);
			t2 = get_time ();
			delta = ((t2 - t1) * 1000000000.0) / cast (f64) iterations;
			update (stbsp_data, delta);
		}
	}
}

write_as_csv :: inline (
	filename : string,
	ryufmt : [BENCH_COUNT]Benchmark_Data,
	ryuc : [BENCH_COUNT]Benchmark_Data,
	stbsp : [BENCH_COUNT]Benchmark_Data
)
{
	builder : String_Builder;
	append (*builder, "Average,");
	for PRECISIONS
	{
		if it_index != 0 then append (*builder, ",");
		print_to_builder (*builder, "Precision = %", it);
	}
	append (*builder, "\n");
	append (*builder, "Ryū format,");
	for data : ryufmt
	{
		if it_index != 0 then append (*builder, ",");
		print_to_builder (*builder, "%", data.mean);
	}
	append (*builder, "\n");
	append (*builder, "Ryū C,");
	for data : ryuc
	{
		if it_index != 0 then append (*builder, ",");
		print_to_builder (*builder, "%", data.mean);
	}
	append (*builder, "\n");
	append (*builder, "stb sprintf,");
	for data : stbsp
	{
		if it_index != 0 then append (*builder, ",");
		print_to_builder (*builder, "%", data.mean);
	}
	append (*builder, "\n");
	write_entire_file (filename, *builder);
}

main :: ()
{
	samples := 10000;
	iterations := 1000;
	precision := 6;

	ryufmt_bench : [BENCH_COUNT]Benchmark_Data;
	ryuc_bench : [BENCH_COUNT]Benchmark_Data;
	stbsp_bench : [BENCH_COUNT]Benchmark_Data;
	print ("Benchmarking fixed form. % samples, % iterations.\n", samples, iterations);
	benchmark (xx samples, xx iterations, *ryufmt_bench, *ryuc_bench, *stbsp_bench, fixed = true);
#if OS == .WINDOWS
	write_as_csv ("win_fixed_form.csv", ryufmt_bench, ryuc_bench, stbsp_bench);
else #if OS == .LINUX
	write_as_csv ("linux_fixed_form.csv", ryufmt_bench, ryuc_bench, stbsp_bench);

	print ("Benchmarking exponent form. % samples, % iterations.\n", samples, iterations);
	benchmark (xx samples, xx iterations, *ryufmt_bench, *ryuc_bench, *stbsp_bench, fixed = false);
#if OS == .WINDOWS
	write_as_csv ("win_exponent_form.csv", ryufmt_bench, ryuc_bench, stbsp_bench);
else #if OS == .LINUX
	write_as_csv ("linux_exponent_form.csv", ryufmt_bench, ryuc_bench, stbsp_bench);
}
