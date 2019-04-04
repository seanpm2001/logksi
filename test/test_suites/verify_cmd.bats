#!/bin/bash

export KSI_CONF=test/test.cfg

@test "CDM test: use invalid stdin combination" {
	run src/logksi verify --log-from-stdin --input-hash - test/resource/interlink/ok-testlog-interlink-1.logsig
	[ "$status" -eq 3 ]
	[[ "$output" =~ "Error: Multiple different simultaneous inputs from stdin (--input-hash -, --log-from-stdin)" ]]
}

@test "CDM test: use invalid stdout combination" {
	run src/logksi verify  test/resource/interlink/ok-testlog-interlink-1 --log - --output-hash -
	[ "$status" -eq 3 ]
	[[ "$output" =~ "Error: Multiple different simultaneous outputs to stdout (--log -, --output-hash -)." ]]
}

@test "verify CMD test: use invalid stdin combination" {
	run src/logksi verify --log-from-stdin --input-hash - test/resource/interlink/ok-testlog-interlink-1.logsig
	[ "$status" -eq 3 ]
	[[ "$output" =~ "Error: Multiple different simultaneous inputs from stdin (--input-hash -, --log-from-stdin)" ]]
}

@test "verify CMD test: use invalid stdout combination" {
	run src/logksi verify  test/resource/interlink/ok-testlog-interlink-1 --log - --output-hash -
	[ "$status" -eq 3 ]
	[[ "$output" =~ "Error: Multiple different simultaneous outputs to stdout (--log -, --output-hash -)." ]]
}

@test "verify CMD test: try to use only one not existing input file"  {
	run src/logksi verify i_do_not_exist
	[ "$status" -eq 3 ]
	[[ "$output" =~ (File does not exist).*(Parameter).*(--input).*(i_do_not_exist) ]]
}

@test "verify CMD test: try to use two not existing input files"  {
	run src/logksi verify i_do_not_exist_1 i_do_not_exist_2
	[ "$status" -eq 3 ]
	[[ "$output" =~ (File does not exist).*(Parameter).*(--input).*(i_do_not_exist_1) ]]
	[[ "$output" =~ (File does not exist).*(Parameter).*(--input).*(i_do_not_exist_2) ]]
}

@test "verify CMD test: try to use two not existing input files after --"  {
	run src/logksi verify -- i_do_not_exist_1 i_do_not_exist_2
	[ "$status" -eq 3 ]
	[[ "$output" =~ (File does not exist).*(Parameter).*(--input).*(i_do_not_exist_1) ]]
	[[ "$output" =~ (File does not exist).*(Parameter).*(--input).*(i_do_not_exist_2) ]]
}

@test "verify CMD test: existing explicitly specified log and log signature file with one unexpected but existing extra file"  {
	run src/logksi verify test/resource/logs_and_signatures/log_repaired test/resource/logs_and_signatures/log_repaired.logsig test/resource/logfiles/unsigned
	[ "$status" -eq 3 ]
	[[ "$output" =~ "Error: Only two inputs (log and log signature file) are required, but there are 3!" ]]
}

@test "verify CMD test: existing explicitly specified log and log signature file with one unexpected token that is not existing file"  {
	run src/logksi verify test/resource/logs_and_signatures/log_repaired i_do_not_exist
	[ "$status" -eq 3 ]
	[[ "$output" =~ (File does not exist).*(Parameter).*(--input).*(i_do_not_exist) ]]
}

@test "verify CMD test: Try to verify log file from stdin and specify multiple input files" {
	run bash -c "echo dummy signature | ./src/logksi verify --log-from-stdin -ddd test/resource/logfiles/unsigned test/resource/logfiles/unsigned"
	[ "$status" -eq 3 ]
	[[ "$output" =~ (Error).*(Log file from stdin [(]--log-from-stdin[)] needs only ONE explicitly specified log signature file, but there are 2)  ]]
}

@test "verify CMD test: Try to verify log file from stdin and from input after --" {
	run bash -c "echo dummy signature | ./src/logksi verify --log-from-stdin -ddd -- test/resource/logfiles/unsigned"
	[ "$status" -eq 3 ]
	[[ "$output" =~ (Error).*(It is not possible to verify both log file from stdin [(]--log-from-stdin[)] and log file[(]s[)] specified after [-][-])  ]]
}

@test "verify CMD test: Try to use invalid publication string: Invalid character" {
	run ./src/logksi verify --ver-pub test/resource/logs_and_signatures/log_repaired --pub-str AAAAAA-C2PMAF-IAISKD-4JLNKD-ZFCF5L-4OWMS5-DMJLTC-DCJ6SS-QDFBC4-ELLWTM-5BO7WF-I7W2J#
	[ "$status" -eq 3 ]
	[[ "$output" =~ (Invalid base32 character).*(Parameter).*(--pub-str).*(AAAAAA-C2PMAF-IAISKD-4JLNKD-ZFCF5L-4OWMS5-DMJLTC-DCJ6SS-QDFBC4-ELLWTM-5BO7WF-I7W2J#) ]]
}

@test "verify CMD test: Try to use invalid publication string: Too short" {
	run ./src/logksi verify --ver-pub test/resource/logs_and_signatures/log_repaired --pub-str AAAAAA-C2PMAF-IAISKD-4JLNKD-ZFCF5L-4OWMS5-DMJLTC-DCJ6SS-QDFBC4-ELLWTM-5BO7WF
	[ "$status" -eq 4 ]
	[[ "$output" =~ (Error).*(Unable parse publication string) ]]
}

@test "verify CMD test: Try to use invalid certificate constraints: Invalid constraints format" {
	run ./src/logksi verify --ver-key test/resource/logs_and_signatures/log_repaired -ddd --ignore-desc-block-time --cnstr = --cnstr =A --cnstr B=
	[ "$status" -eq 3 ]
	[[ "$output" =~ (Parameter is invalid).*(Parameter).*(--cnstr).*(=) ]]
	[[ "$output" =~ (Parameter is invalid).*(Parameter).*(--cnstr).*(=A) ]]
	[[ "$output" =~ (Parameter is invalid).*(Parameter).*(--cnstr).*(B=) ]]
}

@test "verify CMD test: Try to use invalid certificate constraints: Invalid constraints OID" {
	run ./src/logksi verify --ver-key test/resource/logs_and_signatures/log_repaired -ddd --ignore-desc-block-time --cnstr dummy=nothing
	[ "$status" -eq 3 ]
	[[ "$output" =~ (OID is invalid).*(Parameter).*(--cnstr).*(dummy=nothing) ]]
}

@test "verify CMD test: Try to use invalid --time-diff 1" {
	run ./src/logksi verify --ver-key test/resource/logs_and_signatures/log_repaired -d --time-diff "" --time-diff " " --time-diff S --time-diff M --time-diff H --time-diff d --time-diff s --time-diff m --time-diff h --time-diff D
	[ "$status" -eq 3 ]
	[[ "$output" =~ (Parameter has no content).*(Parameter).*(--time-diff).*(\'\') ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(\' \') ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(\'S\') ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(\'M\') ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(\'H\') ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(\'d\') ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(\'s\') ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(\'m\') ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(\'h\') ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(\'D\') ]]
}

@test "verify CMD test: Try to use invalid --time-diff 2" {
	run ./src/logksi verify --ver-key test/resource/logs_and_signatures/log_repaired -d --time-diff 1S2 --time-diff 1S3S --time-diff 1M3M  --time-diff 1H3H  --time-diff 1d3d --time-diff "2 2" --time-diff dHMS --time-diff S5 --time-diff M6 --time-diff H7 --time-diff d8
	[ "$status" -eq 3 ]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(1S2) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(1S3S) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(1M3M) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(1H3H) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(1d3d) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(2 2) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(dHMS) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(S5) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(M6) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(H7) ]]
	[[ "$output" =~ (Only digits and 1x d, H, M and S allowed).*(Parameter).*(--time-diff).*(d8) ]]
}
