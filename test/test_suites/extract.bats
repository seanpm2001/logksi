#!/bin/bash

export KSI_CONF=test/test.cfg

cp -r test/resource/logsignatures/extract.base.logsig test/out
cp -r test/resource/logfiles/extract.base test/out
cp -r test/out/extract.base.logsig test/out/extract.base.1.logsig
cp -r test/out/extract.base test/out/extract.base.1
cp -r test/out/extract.base.logsig test/out/extract.base.2.logsig
cp -r test/out/extract.base test/out/extract.base.2
cp -r test/out/extract.base.logsig test/out/extract.base.3.logsig
cp -r test/out/extract.base test/out/extract.base.3
cp -r test/out/extract.base.logsig test/out/extract.base.4.logsig
cp -r test/out/extract.base test/out/extract.base.4
cp -r test/out/extract.base.logsig test/out/extract.base.5.logsig
cp -r test/out/extract.base test/out/extract.base.5
cp -r test/out/extract.base.logsig test/out/extract.base.6.logsig
cp -r test/out/extract.base test/out/extract.base.6
cp -r test/out/extract.base.logsig test/out/extract.base.7.logsig
cp -r test/out/extract.base test/out/extract.base.7
cp -r test/out/extract.base.logsig test/out/extract.base.8.logsig
cp -r test/out/extract.base test/out/extract.base.8
cp -r test/out/extract.base.logsig test/out/extract.base.9.logsig
cp -r test/out/extract.base test/out/extract.base.9
cp -r test/out/extract.base.logsig test/out/extract.base.10.logsig
cp -r test/out/extract.base test/out/extract.base.10
cp -r test/resource/logsignatures/legacy_extract.gtsig test/out
cp -r test/resource/logfiles/legacy_extract test/out

@test "extract record 1" {
	run ./src/logksi extract test/out/extract.base -r 1 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.base -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.base.excerpt test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, specify log records file" {
	run ./src/logksi extract test/out/extract.base.1 --out-log test/out/extract.user.1.excerpt -r 1 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.user.1.excerpt test/out/extract.base.1.excerpt.logsig -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.user.1.excerpt test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, specify integrity proof file" {
	run ./src/logksi extract test/out/extract.base.2 --out-proof test/out/extract.user.2.excerpt.logsig -r 1 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.base.2.excerpt test/out/extract.user.2.excerpt.logsig -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.base.2.excerpt test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, specify both output files" {
	run ./src/logksi extract test/out/extract.base.3 --out-log test/out/extract.user.3.excerpt --out-proof test/out/extract.user.3.excerpt.logsig -r 1 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.user.3.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.user.3.excerpt test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, specify output" {
	run ./src/logksi extract test/out/extract.base.4 -o test/out/extract.user.4 -r 1 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.user.4.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.user.4.excerpt test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, specify output, override log records" {
	run ./src/logksi extract test/out/extract.base.5 -o test/out/extract.user.5 --out-log test/out/extract.user.5.1 -r 1 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.user.5.1 test/out/extract.user.5.excerpt.logsig -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.user.5.1 test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, specify output, override integrity proof" {
	run ./src/logksi extract test/out/extract.base.6 -o test/out/extract.user.6 --out-proof test/out/extract.user.6.1 -r 1 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.user.6.excerpt test/out/extract.user.6.1 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.user.6.excerpt test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, redirect log records to stdout" {
	run bash -c "./src/logksi extract test/out/extract.base.7 --out-log - -r 1 -d > test/out/extract.user.7.stdout"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.user.7.stdout test/out/extract.base.7.excerpt.logsig -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.user.7.stdout test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, redirect integrity proof to stdout" {
	run bash -c "./src/logksi extract test/out/extract.base.8 --out-proof - -r 1 -d > test/out/extract.user.8.stdout"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.base.8.excerpt test/out/extract.user.8.stdout -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.base.8.excerpt test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, attempt to redirect both outputs to stdout" {
	run bash -c "./src/logksi extract test/out/extract.base.8 --out-log - --out-proof - -r 1 -d"
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Both output files cannot be redirected to stdout." ]]
	run bash -c "./src/logksi extract test/out/extract.base.8 -o - -r 1 -d"
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Both output files cannot be redirected to stdout." ]]
}

@test "extract record 1, read log file from stdin" {
	run bash -c "cat test/out/extract.base.9 | ./src/logksi extract --log-from-stdin test/out/extract.base.9.logsig -o test/out/extract.user.9 -r 1 -d"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.user.9.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.user.9.excerpt test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, read signature file from stdin" {
	run bash -c "cat test/out/extract.base.10.logsig | ./src/logksi extract test/out/extract.base.10 --sig-from-stdin -r 1 -d"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.base.10.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.base.10.excerpt test/resource/logfiles/r1.excerpt
	[ "$status" -eq 0 ]
}

@test "extract record 1, attempt to read both files from stdin" {
	run ./src/logksi extract --log-from-stdin --sig-from-stdin -r 1 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Maybe you want to:" ]]
}

@test "extract record 1, attempt to read one file from stdin without specifying the other input file" {
	run ./src/logksi extract --log-from-stdin -r 1 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "You have to define flag(s) '--input'." ]]
	run ./src/logksi extract --sig-from-stdin -r 1 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "You have to define flag(s) '--input'." ]]
}

@test "extract record 1, attemp to read log file from stdin without specifying the output file" {
	run ./src/logksi extract --log-from-stdin test/out/extract.base.10.logsig -r 1 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Output log records file name must be specified if log file is read from stdin." ]]
	run ./src/logksi extract --log-from-stdin test/out/extract.base.10.logsig --out-log test/out/extract.user.10.excerpt -r 1 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Output integrity proof file name must be specified if log file is read from stdin." ]]
}

@test "verify record 1 modified" {
	run ./src/logksi verify test/resource/logfiles/r1_modified.excerpt test/out/extract.base.excerpt.logsig -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Block no. 1: record hashes not equal." ]]
	[[ "$output" =~ "Log signature verification failed." ]]
}

@test "verify record 1 too long" {
	run ./src/logksi verify test/resource/logfiles/r1_too_long.excerpt test/out/extract.base.excerpt.logsig -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Block no. 1: end of log file contains unexpected records." ]]
	[[ "$output" =~ "Log signature verification failed." ]]
}

@test "verify proof wrong record hash" {
	run ./src/logksi verify test/out/extract.base.excerpt test/resource/logsignatures/proof_wrong_record_hash.excerpt.logsig -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Block no. 1: record hashes not equal." ]]
	[[ "$output" =~ "Log signature verification failed." ]]
}

@test "verify proof wrong sibling hash 1" {
	run ./src/logksi verify test/out/extract.base.excerpt test/resource/logsignatures/proof_wrong_sibling_hash_1.excerpt.logsig -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Block no. 1: root hashes not equal." ]]
	[[ "$output" =~ "Log signature verification failed." ]]
}

@test "verify proof wrong sibling hash 3" {
	run ./src/logksi verify test/out/extract.base.excerpt test/resource/logsignatures/proof_wrong_sibling_hash_3.excerpt.logsig -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Block no. 1: root hashes not equal." ]]
	[[ "$output" =~ "Log signature verification failed." ]]
}

@test "verify proof wrong level correction 1" {
	run ./src/logksi verify test/out/extract.base.excerpt test/resource/logsignatures/proof_wrong_level_correction_1.excerpt.logsig -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Block no. 1: root hashes not equal." ]]
	[[ "$output" =~ "Log signature verification failed." ]]
}

@test "verify proof wrong level correction 2" {
	run ./src/logksi verify test/out/extract.base.excerpt test/resource/logsignatures/proof_wrong_level_correction_2.excerpt.logsig -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Block no. 1: root hashes not equal." ]]
	[[ "$output" =~ "Log signature verification failed." ]]
}

@test "verify proof wrong link direction" {
	run ./src/logksi verify test/out/extract.base.excerpt test/resource/logsignatures/proof_wrong_link_direction.excerpt.logsig -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Block no. 1: root hashes not equal." ]]
	[[ "$output" =~ "Log signature verification failed." ]]
}

@test "extract last (log)record" {
	run ./src/logksi extract test/out/extract.base -r 1414 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.base.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.base.excerpt test/resource/logfiles/r1414.excerpt
	[ "$status" -eq 0 ]
}

@test "extract range over three blocks" {
	run ./src/logksi extract test/out/extract.base -r 3-7 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.base.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.base.excerpt test/resource/logfiles/r3-7.excerpt
	[ "$status" -eq 0 ]
}

@test "extract range over three blocks, alternative range definition 1" {
	run ./src/logksi extract test/out/extract.base -r 3-5,6,7 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.base.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.base.excerpt test/resource/logfiles/r3-7.excerpt
	[ "$status" -eq 0 ]
}

@test "extract range over three blocks, alternative range definition 2" {
	run ./src/logksi extract test/out/extract.base -r 3,4,5-7 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.base.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.base.excerpt test/resource/logfiles/r3-7.excerpt
	[ "$status" -eq 0 ]
}

@test "extract range over three blocks, isolated positions" {
	run ./src/logksi extract test/out/extract.base -r 3,6,9 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/extract.base.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/extract.base.excerpt test/resource/logfiles/r3.6.9.excerpt
	[ "$status" -eq 0 ]
}

@test "extract records from non-extended legacy.gtsig" {
	run ./src/logksi verify test/out/legacy_extract -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Warning: RFC3161 timestamp(s) found in log signature." ]]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi extract test/out/legacy_extract -r 1-20 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Warning: RFC3161 timestamp(s) found in log signature." ]]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/legacy_extract.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/legacy_extract.excerpt test/resource/logfiles/legacy_extract.r1-20.excerpt
	[ "$status" -eq 0 ]
}

@test "extract records from extended legacy.gtsig" {
	run ./src/logksi extend test/out/legacy_extract --enable-rfc3161-conversion -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi extract test/out/legacy_extract -r 21-204 -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run ./src/logksi verify test/out/legacy_extract.excerpt -d
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
	run diff test/out/legacy_extract.excerpt test/resource/logfiles/legacy_extract.r21-204.excerpt
	[ "$status" -eq 0 ]
}

@test "attempt to extract a range given in descending order" {
	run ./src/logksi extract test/out/extract.base -r 7-3 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must be given in strictly ascending order." ]]
}

@test "attempt to extract a list that contains duplicates" {
	run ./src/logksi extract test/out/extract.base -r 3,4,5-7,7 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must be given in strictly ascending order." ]]
}

@test "attempt to extract a list of ranges given in descending order" {
	run ./src/logksi extract test/out/extract.base -r 6-7,3-5 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must be given in strictly ascending order." ]]
}

@test "attempt to extract a list that contains non-positive numbers" {
	run ./src/logksi extract test/out/extract.base -r 6,-7 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 6,7-8,-9 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 6,7--8,9 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 0,3 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 0-3 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r -3-3 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
}

@test "attempt to extract a list that contains syntax errors" {
	run ./src/logksi extract test/out/extract.base -r , -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 5, -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r - -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 6- -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 5,,6 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 5-6-7 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
}

@test "attempt to extract a list that contains whitepace" {
	run ./src/logksi extract test/out/extract.base -r "5 6" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r "5 ,6" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r "5, 6" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r "5 -7" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r "5- 7" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r "5,7 " -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r " 5-7" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r " 5\t7" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r " 5\n7" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r " 5\v7" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r " 5\f7" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
	run ./src/logksi extract test/out/extract.base -r " 5\r7" -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: List of positions must not contain whitespace. Use ',' and '-' as separators." ]]
}

@test "attempt to extract a list that contains non-decimal integers" {
	run ./src/logksi extract test/out/extract.base -r 0x5 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 0X5 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 5,0x6 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r 5-0X6 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
}

@test "attempt to extract a list that contains illegal characters" {
	run ./src/logksi extract test/out/extract.base -r a -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r Z -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r + -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r * -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r % -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r $ -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r . -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
	run ./src/logksi extract test/out/extract.base -r : -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Positions must be represented by positive decimal integers, using a list of comma-separated ranges." ]]
}

@test "attempt to extract a list that contains positions out of range" {
	run ./src/logksi extract test/out/extract.base -r 1415 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Extract position 1415 out of range - not enough loglines." ]]
	run ./src/logksi extract test/out/extract.base -r 1413-1416 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Extract position 1415 out of range - not enough loglines." ]]
	run ./src/logksi extract test/out/extract.base -r 1413,1414,1415,1416 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Extract position 1415 out of range - not enough loglines." ]]
	run ./src/logksi extract test/out/extract.base -r 1-999999999999999 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Extract position 1415 out of range - not enough loglines." ]]
	run ./src/logksi extract test/out/legacy_extract -r 1-205 -d
	[ "$status" -ne 0 ]
	[[ "$output" =~ "Error: Extract position 205 out of range - not enough loglines." ]]
}
