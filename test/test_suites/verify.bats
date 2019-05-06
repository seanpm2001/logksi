#!/bin/bash

export KSI_CONF=test/test.cfg

@test "Try to verify parts files as log signature." {
	run src/logksi verify test/resource/logsignatures/signed.logsig.parts/blocks.dat test/resource/logsignatures/signed.logsig.parts/block-signatures.dat -d
	[ "$status" -eq 4 ]
	[[ ! "$output" =~ "Summary of logfile" ]]
	[[ "$output" =~ "Error: Log signature file identification magic number not found." ]]
	[[ "$output" =~ "Error: Expected file types {LOGSIG11, LOGSIG12, RECSIG11, RECSIG12} but got LOG12SIG!" ]]

	run src/logksi verify test/resource/logsignatures/signed.logsig.parts/block-signatures.dat test/resource/logsignatures/signed.logsig.parts/blocks.dat
	[ "$status" -eq 4 ]
	[[ "$output" =~ "Error: Log signature file identification magic number not found." ]]
	[[ "$output" =~ "Error: Expected file types {LOGSIG11, LOGSIG12, RECSIG11, RECSIG12} but got LOG12BLK!" ]]
}

@test "Try to verify log file as log signature." {
	run src/logksi verify test/resource/logs_and_signatures/unsigned test/resource/logs_and_signatures/unsigned
	[ "$status" -eq 4 ]
	[[ "$output" =~ "Error: Log signature file identification magic number not found." ]]
	[[ "$output" =~ "Error: Expected file types {LOGSIG11, LOGSIG12, RECSIG11, RECSIG12} but got <unknown file version>!" ]]
}

@test "verify log_repaired.logsig" {
	run ./src/logksi verify test/resource/logs_and_signatures/log_repaired -ddd --ignore-desc-block-time
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
}

@test "verify log_repaired.logsig internally" {
	run ./src/logksi verify --ver-int test/resource/logs_and_signatures/log_repaired -ddd --ignore-desc-block-time
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
}

@test "verify log_repaired.logsig against calendar" {
	run ./src/logksi verify --ver-cal test/resource/logs_and_signatures/log_repaired -ddd --ignore-desc-block-time
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
}

@test "verify log_repaired.logsig against key" {
	run ./src/logksi verify --ver-key test/resource/logs_and_signatures/log_repaired -ddd --ignore-desc-block-time
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
}

@test "verify log_repaired.logsig WITHOUT --ignore-desc-block-time" {
	run ./src/logksi verify test/resource/logs_and_signatures/log_repaired
	[ "$status" -eq 6 ]
	[[ "$output" =~ .*(Error).*(Block no).*(17).*(1540303365).*(in file).*(log_repaired).*(is more recent than).*(block no).*(18).*(1517928940).* ]]
	[[ "$output" =~ .*(Error).*(Block no).*(25).*(1540303366).*(in file).*(log_repaired).*(is more recent than).*(block no).*(26).*(1517928947).* ]]
}

@test "try verifying log_repaired.logsig against signed logfile" {
	run ./src/logksi verify test/resource/logs_and_signatures/signed test/resource/logs_and_signatures/log_repaired.logsig -ddd
	[ "$status" -ne 0 ]
	[[ "$output" =~ "failed to verify logline no. 1:" ]]
	[[ "$output" =~ "Log signature verification failed." ]]
}

@test "verify compressed log from stdin" {
	run bash -c "zcat < test/resource/logfiles/secure.gz | ./src/logksi verify test/resource/logsignatures/secure.logsig --log-from-stdin -ddd"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Finalizing log signature... ok." ]]
}

@test "warn about consecutive blocks that has same signing time" {
	run src/logksi verify test/resource/logfiles/unsigned test/resource/logsignatures/unsigned-same-sign-time.logsig --ignore-desc-block-time --warn-same-block-time
	[ "$status" -eq 0 ]
	[[ "$output" =~ .*(Warning).*(Block).*(1).*(and).*(2).*(in file).*(unsigned).*(has same signing time).*(1540389597).* ]]
}

@test "verify log signature with expected client ID" {
	run src/logksi verify test/resource/logs_and_signatures/signed -d --client-id "GT :: .* :: GT :: anon"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying... ok." ]]
}

@test "verify log signature with expected client ID using more complex client id pattern" {
	run src/logksi verify test/resource/continue-verification/log test/resource/continue-verification/log-ok-one-sig-diff-client-id.logsig  -d --client-id "GT :: GT :: GT :: (anon|sha512)" --ignore-desc-block-time
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying... ok." ]]
}

@test "verify log signature with expected client ID using more complex client id pattern and enabled warnings" {
	run src/logksi verify test/resource/continue-verification/log test/resource/continue-verification/log-ok-one-sig-diff-client-id.logsig  -d --client-id "GT :: GT :: GT :: (anon|sha512)" --ignore-desc-block-time --warn-client-id-change
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying... ok." ]]
	[[ "$output" =~ "o Warning: Client ID in block 2 is not constant" ]]
}

@test "verify log signature with unexpected client ID" {
	run src/logksi verify test/resource/logs_and_signatures/signed -d --client-id "GT :: KT :: GT :: anon"
	[ "$status" -eq 1 ]
	[[ "$output" =~ (Error: Client ID mismatch).*(GT :: GT :: GT :: anon).*(Error: Not matching pattern).*(GT :: KT :: GT :: anon) ]]
}

@test "verify log signature with unexpected client ID using more complex client ID pattern" {
	run src/logksi verify test/resource/continue-verification/log test/resource/continue-verification/log-ok-one-sig-diff-client-id.logsig  -d --client-id "GT :: GT :: GT :: (anon|Xsha512X)" --ignore-desc-block-time
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Verifying... failed." ]]
	[[ "$output" =~ (Error: Client ID mismatch).*(GT :: GT :: GT :: sha512).*(Error: Not matching pattern).*(GT :: GT :: GT :: .anon|Xsha512X.) ]]
}

@test "verify log signature with unexpected client ID using more complex client ID pattern and enabled warnings" {
	run src/logksi verify test/resource/continue-verification/log test/resource/continue-verification/log-ok-one-sig-diff-client-id.logsig  -d --client-id "GT :: GT :: GT :: (anon|Xsha512X)" --ignore-desc-block-time --warn-client-id-change
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Verifying... failed." ]]
	[[ "$output" =~ (Error: Client ID mismatch).*(GT :: GT :: GT :: sha512).*(Error: Not matching pattern).*(GT :: GT :: GT :: .anon|Xsha512X.) ]]
	[[ ! "$output" =~ "o Warning: Client ID in block.*is not constant" ]]
}

@test "verify log signature with changing client ID and with enabled warnings" {
	run src/logksi verify test/resource/continue-verification/log test/resource/continue-verification/log-ok-one-sig-diff-client-id.logsig  -d --warn-client-id-change --ignore-desc-block-time
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying... ok." ]]
	[[ "$output" =~ ( o Warning: Client ID in block 2 is not constant:).*(Expecting: .GT :: GT :: GT :: anon.).*(But is:    .GT :: GT :: GT :: sha512.) ]]
}

@test "verify excerpt file with expected client ID" {
	run src/logksi verify test/resource/excerpt/log-ok.excerpt -d  --client-id "GT :: .* :: GT :: anon"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying... ok." ]]
}

@test "verify excerpt file with expected client ID using more complex client id pattern" {
	run src/logksi verify test/resource/excerpt/diff-client-id.excerpt -d --client-id "GT :: GT :: GT :: (anon|sha512)"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying... ok." ]]
}

@test "verify excerpt file with unexpected client ID" {
	run src/logksi verify test/resource/excerpt/log-ok.excerpt -d --client-id "GT :: KT :: GT :: anon"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Verifying... failed." ]]
	[[ "$output" =~ (Error: Client ID mismatch).*(GT :: GT :: GT :: anon).*(Error: Not matching pattern).*(GT :: KT :: GT :: anon) ]]
}

@test "verify excerpt file with changing client ID and with enabled warnings" {
	run src/logksi verify test/resource/excerpt/diff-client-id.excerpt -d --warn-client-id-change
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying... ok." ]]
	[[ "$output" =~ ( o Warning: Client ID in block 2 is not constant:).*(Expecting: .GT :: GT :: GT :: anon.).*(But is:    .GT :: GT :: GT :: sha512.) ]]
}

@test "verify with --block-time-diff to detect same signing time, ignore negative diff (1,oo)" {
	run src/logksi verify test/resource/logfiles/unsigned test/resource/logsignatures/unsigned-same-sign-time.logsig --ignore-desc-block-time -d --block-time-diff 1,oo
	[ "$status" -eq 6 ]
	[[ "$output" =~ "Verifying... failed." ]]
	[[ "$output" =~ (Error: Blocks 1.*1540389597.*and 2.*1540389597.*signing times are too close.*00:00:00 does not fit into 00:00:01 - oo) ]]
}

@test "verify with --block-time-diff to detect blocks that are too apart, ignore negative diff (259d)" {
	run src/logksi verify test/resource/logfiles/unsigned test/resource/logsignatures/unsigned-same-sign-time.logsig --ignore-desc-block-time -d --block-time-diff 259d
	[ "$status" -eq 6 ]
	[[ "$output" =~ "Verifying... failed." ]]
	[[ "$output" =~ (Error: Blocks 4).*(1517928939).*(and 5).*(1540377483).*(signing times are too apart).*(259d 19:42:24 does not fit into 0 - 259d 00:00:00) ]]
}

@test "verify with --block-time-diff only negative or 0 diff is accepted (-oo)" {
	run src/logksi verify test/resource/logfiles/unsigned test/resource/logsignatures/unsigned-same-sign-time.logsig -d --block-time-diff -oo
	[ "$status" -eq 6 ]
	[[ "$output" =~ "Verifying... failed." ]]
	[[ "$output" =~ (Error: Blocks 3).*(1517928938).*(and 4).*(1517928939).*(signing times are too apart).*(00:00:01 does not fit into -oo - 0) ]]
}

@test "verify with --block-time-diff to detect block that are too apart (exact match), ignore negative diff (259d23H4M19)" {
	run src/logksi verify test/resource/logfiles/unsigned test/resource/logsignatures/unsigned-same-sign-time.logsig --ignore-desc-block-time -d --block-time-diff 259d23H4M19
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying... ok." ]]
	[[ ! "$output" =~ (are too apart) ]]
	[[ ! "$output" =~ (are too close) ]]
}

@test "verify with --block-time-diff using infinity (-oo,oo)" {
	run src/logksi verify test/resource/logfiles/unsigned test/resource/logsignatures/unsigned-same-sign-time.logsig -d --block-time-diff -oo,oo
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verifying... ok." ]]
	[[ ! "$output" =~ (are too apart) ]]
	[[ ! "$output" =~ (are too close) ]]
}