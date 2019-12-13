/*
 * Copyright 2013-2019 Guardtime, Inc.
 *
 * This file is part of the Guardtime client SDK.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES, CONDITIONS, OR OTHER LICENSES OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 * "Guardtime" and "KSI" are trademarks or registered trademarks of
 * Guardtime, Inc., and no license to trademarks is granted; Guardtime
 * reserves and retains all trademark rights.
 */

#include <string.h>
#include <stdlib.h>
#include <ksi/ksi.h>
#include <ksi/tlv_element.h>
#include <ctype.h>
#include "param_set/param_set.h"
#include "param_set/strn.h"
#include "err_trckr.h"
#include "logksi_err.h"
#include "api_wrapper.h"
#include "printer.h"
#include "debug_print.h"
#include "tlv_object.h"
#include "extract_info.h"
#include "io_files.h"
#include "rsyslog.h"
#include "check.h"
#include "process.h"
#include "logksi.h"

static int count_blocks(ERR_TRCKR *err, KSI_CTX *ksi, LOGKSI *logksi, SMART_FILE *in);
static int skip_current_block_as_it_does_not_verify(LOGKSI *logksi, MULTI_PRINTER* mp, IO_FILES *files, ERR_TRCKR *err, KSI_CTX *ksi, int *skip);
static int wrapper_LOGKSI_createSignature(PARAM_SET *set, MULTI_PRINTER *mp, ERR_TRCKR *err, KSI_CTX *ksi, LOGKSI *logksi, IO_FILES *files, KSI_DataHash *hash, KSI_uint64_t rootLevel, KSI_Signature **sig);
static int logksi_new_record_chain(MERKLE_TREE *tree, void *ctx, int isMetaRecordHash, KSI_DataHash *hash);
static int logksi_extract_record_chain(MERKLE_TREE *tree, void *ctx, unsigned char level, KSI_DataHash *leftLink);;




int logsignature_extend(PARAM_SET *set, MULTI_PRINTER* mp, ERR_TRCKR *err, KSI_CTX *ksi, KSI_PublicationsFile* pubFile, EXTENDING_FUNCTION extend_signature, IO_FILES *files) {
	int res;
	LOGKSI logksi;
	unsigned char ftlv_raw[SOF_FTLV_BUFFER];
	SIGNATURE_PROCESSORS processors;
	KSI_DataHash *theFirstInputHashInFile = NULL;

	if (set == NULL || err == NULL || ksi == NULL || extend_signature == NULL || files == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	LOGKSI_initialize(&logksi);
	logksi.ftlv_raw = ftlv_raw;
	logksi.taskId = TASK_EXTEND;
	logksi.err = err;
	memset(&processors, 0, sizeof(processors));
	processors.extend_signature = extend_signature;

	res = MERKLE_TREE_new(&logksi.tree);
	if (res != KT_OK) goto cleanup;

	logksi.isContinuedOnFail = PARAM_SET_isSetByName(set, "continue-on-fail");

	res = process_magic_number(set, mp, err, &logksi, files);
	if (res != KT_OK) goto cleanup;

	if (logksi.file.version == RECSIG11 || logksi.file.version == RECSIG12) {
		res = KT_VERIFICATION_SKIPPED;
		ERR_TRCKR_ADD(err, res, "Extending of excerpt file not yet implemented!");
		goto cleanup;
	}

	while (!SMART_FILE_isEof(files->files.inSig)) {
		MULTI_PRINTER_printByID(mp, MP_ID_BLOCK);

		res = LOGKSI_FTLV_smartFileRead(files->files.inSig, logksi.ftlv_raw, SOF_FTLV_BUFFER, &logksi.ftlv_len, &logksi.ftlv);
		if (res == KSI_OK) {
			switch (logksi.ftlv.tag) {
				case 0x901:
					if (theFirstInputHashInFile == NULL) theFirstInputHashInFile = KSI_DataHash_ref(logksi.block.inputHash);
				case 0x902:
				case 0x903:
				case 0x911:
				case 0x904:
					res = process_log_signature_with_block_signature(set, mp, err, &logksi, files, ksi, &processors, pubFile);
					if (res != KT_OK) goto cleanup;
				break;

				default:
					/* TODO: unknown TLV found. Either
					 * 1) Warn user and skip TLV
					 * 2) Copy TLV (maybe warn user)
					 * 3) Abort extending with an error
					 */
				break;
			}
		} else {
			if (logksi.ftlv_len > 0) {
				res = KT_INVALID_INPUT_FORMAT;
				ERR_CATCH_MSG(err, res, "Error: Block no. %zu: incomplete data found in log signature file.", logksi.blockNo);
			} else {
				break;
			}
		}
	}

	res = finalize_log_signature(set, mp, err, &logksi, files, ksi, theFirstInputHashInFile);
	if (res != KT_OK) goto cleanup;

	res = KT_OK;

cleanup:

	LOGKSI_freeAndClearInternals(&logksi);
	KSI_DataHash_free(theFirstInputHashInFile);

	return res;
}

int logsignature_verify(PARAM_SET *set, MULTI_PRINTER* mp, ERR_TRCKR *err, KSI_CTX *ksi, LOGKSI *logksi, KSI_DataHash *firstLink, VERIFYING_FUNCTION verify_signature, IO_FILES *files, KSI_DataHash **lastLeaf, uint64_t* last_rec_time) {
	int res;

	KSI_DataHash *theFirstInputHashInFile = NULL;
	unsigned char ftlv_raw[SOF_FTLV_BUFFER];
	SIGNATURE_PROCESSORS processors;
	int isFirst = 1;
	int skipCurrentBlock = 0;
	int printHeader = 0;
	REGEXP *tmp_regxp = NULL;
	KSI_DataHash *prevLeaf = NULL;
	static uint64_t lastSignatureTime = 0;


	if (set == NULL || err == NULL || ksi == NULL || logksi == NULL || verify_signature == NULL || files == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	logksi->ftlv_raw = ftlv_raw;
	logksi->taskId = TASK_VERIFY;
	logksi->err = err;
	memset(&processors, 0, sizeof(processors));
	processors.verify_signature = verify_signature;

	res = MERKLE_TREE_new(&logksi->tree);
	if (res != KT_OK) goto cleanup;

	logksi->isContinuedOnFail = PARAM_SET_isSetByName(set, "continue-on-fail");
	logksi->sigTime_0 = lastSignatureTime;

	res = process_magic_number(set, mp, err, logksi, files);
	if (res != KT_OK) goto cleanup;

	if (PARAM_SET_isSetByName(set, "client-id")) {
		char *pattern = NULL;
		PARAM_SET_getStr(set, "client-id", NULL, PST_PRIORITY_HIGHEST, PST_INDEX_LAST, &pattern);

		res = REGEXP_new(pattern, &tmp_regxp);
		ERR_CATCH_MSG(err, res, "Error: Unable to parse regular expression for matching the client ID.");

		logksi->task.verify.client_id_match = tmp_regxp;
		tmp_regxp = NULL;
	}


	while (!SMART_FILE_isEof(files->files.inSig)) {
		MULTI_PRINTER_printByID(mp, MP_ID_BLOCK);

		res = LOGKSI_FTLV_smartFileRead(files->files.inSig, logksi->ftlv_raw, SOF_FTLV_BUFFER, &logksi->ftlv_len, &logksi->ftlv);
		if (res == KSI_OK) {
			skip_current_block_as_it_does_not_verify(logksi, mp, files, err, ksi, &skipCurrentBlock);
			if (skipCurrentBlock) continue;

			switch (logksi->file.version) {
				case LOGSIG11:
				case LOGSIG12:
					switch (logksi->ftlv.tag) {
						case 0x904:
						case 0x901:
						case 0x902:
						case 0x903:
						case 0x911:
							res = process_log_signature_with_block_signature(set, mp, err, logksi, files, ksi, &processors, NULL);
							if (res != KT_OK) {
								/* In case of verification failure and --continue-on-fail option, verification is continued. */
								if ((res == KT_VERIFICATION_FAILURE || res == KSI_VERIFICATION_FAILURE) && logksi->isContinuedOnFail) {
									print_progressResult(mp, MP_ID_BLOCK, DEBUG_LEVEL_1, res);
									print_progressResult(mp, MP_ID_BLOCK, DEBUG_LEVEL_2, res);
									print_progressResult(mp, MP_ID_BLOCK, DEBUG_LEVEL_3, res);

									logksi->quietError = KT_VERIFICATION_FAILURE;

									skipCurrentBlock = 1;
									logksi->task.verify.lastBlockWasSkipped = 1;

									print_debug_mp(mp, MP_ID_BLOCK_ERRORS, DEBUG_SMALLER | DEBUG_LEVEL_3, "\n x Error: Skipping block %zu!\n", logksi->blockNo);
									print_debug_mp(mp, MP_ID_BLOCK_ERRORS, DEBUG_EQUAL | DEBUG_LEVEL_3, "Block no. %3zu: Error: Block is skipped!\n", logksi->blockNo);
									res = KT_OK;
									continue;
								}
								goto cleanup;
							}
						break;

						default:
							/* TODO: unknown TLV found. Either
							 * 1) Warn user and skip TLV
							 * 2) Copy TLV (maybe warn user)
							 * 3) Abort extending with an error
							 */
						break;
					}

					/* Addidional post processor for block header. */
					if (logksi->ftlv.tag == 0x901) {
						char buf[256];

						res = MERKLE_TREE_getPrevLeaf(logksi->tree, &prevLeaf);
						ERR_CATCH_MSG(err, res, "Error: Unable to get previous leaf.");

						LOGKSI_DataHash_toString(prevLeaf, buf, sizeof(buf));
						print_progressResult(mp, MP_ID_BLOCK, DEBUG_EQUAL | DEBUG_LEVEL_2, res);
						if (theFirstInputHashInFile == NULL) theFirstInputHashInFile = KSI_DataHash_ref(prevLeaf);

						print_debug_mp(mp, MP_ID_BLOCK, DEBUG_LEVEL_3, "Block no. %3zu: input hash: %s.\n", logksi->blockNo, buf);

						print_progressDesc(mp, MP_ID_BLOCK, 0, DEBUG_EQUAL | DEBUG_LEVEL_2 , "Verifying block no. %3zu... ", logksi->blockNo);


						/* Check if the last leaf from the previous block matches with the current first block. */
						if (isFirst == 1 && firstLink != NULL) {
							print_progressDesc(mp, MP_ID_BLOCK, 0, DEBUG_LEVEL_3, "Block no. %3zu: verifying inter-linking input hash... ", logksi->blockNo);
							isFirst = 0;
							if (!KSI_DataHash_equals(firstLink, prevLeaf)) {
								char buf_imp[1024];
								char buf_exp_imp[1024];
								char buf_fname[4096];
								char *prevBlockSource = "Unexpected and not initialized previous block source.";
								const char *firstBlockSource = IO_FILES_getCurrentLogFilePrintRepresentation(files);

								res = KT_VERIFICATION_FAILURE;

								if (PARAM_SET_isSetByName(set, "input-hash") && files->previousLogFile[0] == '\0') {
									char *fname = NULL;
									PARAM_SET_getStr(set, "input-hash", NULL, PST_PRIORITY_HIGHEST, PST_INDEX_LAST, &fname);

									PST_snprintf(buf_fname, sizeof(buf_fname), "from --input-hash %s", fname);
									prevBlockSource = buf_fname;
								} else {
									prevBlockSource = files->previousLogFile;
								}

								ERR_TRCKR_ADD(err, res, "Error: Block no. %zu: The last leaf from the previous block (%s) does not match with the current first block (%s). Expecting '%s', but got '%s'.", logksi->blockNo, prevBlockSource, firstBlockSource, LOGKSI_DataHash_toString(firstLink, buf_exp_imp, sizeof(buf_exp_imp)), LOGKSI_DataHash_toString(prevLeaf, buf_imp, sizeof(buf_imp)));

								goto cleanup;
							}

							print_progressResult(mp, MP_ID_BLOCK, DEBUG_LEVEL_3, res);
						}

						KSI_DataHash_free(prevLeaf);
						prevLeaf = NULL;
					}

				break;

				case RECSIG11:
				case RECSIG12:
					switch (logksi->ftlv.tag) {
						case 0x905:
						{
							char strT1[256];
							logksi->file.nofTotalRecordHashes += logksi->block.nofRecordHashes;
							if (MULTI_PRINTER_hasDataByID(mp, MP_ID_BLOCK_PARSING_TREE_NODES)) {
								print_debug_mp(mp, MP_ID_BLOCK_PARSING_TREE_NODES, DEBUG_LEVEL_3, "}\n");
								MULTI_PRINTER_printByID(mp, MP_ID_BLOCK_PARSING_TREE_NODES);
							}

							if ((logksi->file.recTimeMin == 0 || logksi->file.recTimeMin > logksi->block.recTimeMin) && logksi->block.recTimeMin > 0) logksi->file.recTimeMin = logksi->block.recTimeMin;
							if (logksi->file.recTimeMax == 0 || logksi->file.recTimeMax < logksi->block.recTimeMax) logksi->file.recTimeMax = logksi->block.recTimeMax;

							print_progressResult(mp, MP_ID_BLOCK, DEBUG_LEVEL_2, res);
							if (MULTI_PRINTER_hasDataByID(mp, MP_ID_BLOCK_SUMMARY)) {
								print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, " * %-*s%zu\n", SIZE_OF_LONG_INDENTATION, "Record count:", logksi->block.nofRecordHashes);
								if (logksi->block.recTimeMin > 0) {
									print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, " * %-*s%s\n", SIZE_OF_LONG_INDENTATION, "First record time:", LOGKSI_uint64_toDateString(logksi->block.recTimeMin, strT1, sizeof(strT1)));
								}

								if (logksi->block.recTimeMax > 0) {
									print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, " * %-*s%s\n", SIZE_OF_LONG_INDENTATION, "Last record time:", LOGKSI_uint64_toDateString(logksi->block.recTimeMax, strT1, sizeof(strT1)));
									print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, " * %-*s%s\n", SIZE_OF_LONG_INDENTATION, "Block duration:", time_diff_to_string(logksi->block.recTimeMax - logksi->block.recTimeMin, strT1, sizeof(strT1)));
								}

								print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, "\n", SIZE_OF_LONG_INDENTATION, "Record count:", logksi->block.nofRecordHashes);


								MULTI_PRINTER_printByID(mp, MP_ID_BLOCK);
								MULTI_PRINTER_printByID(mp, MP_ID_BLOCK_ERRORS);
								MULTI_PRINTER_printByID(mp, MP_ID_BLOCK_SUMMARY);
							}
							print_progressDesc(mp, MP_ID_BLOCK, 0, DEBUG_EQUAL | DEBUG_LEVEL_2 , "Verifying block no. %3zu... ", logksi->blockNo + 1);
							res = process_ksi_signature(set, mp, err, logksi, files, ksi, &processors);
							if (res != KT_OK) goto cleanup;

							logksi->block.nofRecordHashes = 0;
							logksi->block.recTimeMin = 0;

							LOGKSI_uint64_toDateString(logksi->block.sigTime_1, strT1, sizeof(strT1));

							print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, "\nSummary of block %zu:\n", logksi->blockNo);
							print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, " * %-*s%s\n", SIZE_OF_SHORT_INDENTENTION, "Sig time:", strT1);

							printHeader = 1;
						}
						break;

						case 0x907:
						{
						if (printHeader) {
							print_debug_mp(mp, MP_ID_BLOCK_PARSING_TREE_NODES, DEBUG_LEVEL_3, "Block no. %3zu: {", logksi->blockNo);
							printHeader = 0;
						}
							print_debug_mp(mp, MP_ID_BLOCK_PARSING_TREE_NODES, DEBUG_LEVEL_3, "r" );
							res = process_record_chain(set, mp, err, logksi, files, ksi);
							if (res != KT_OK) goto cleanup;

							res = check_log_record_embedded_time_against_ksi_signature_time(set, mp, err, logksi);
							if (res != KT_OK) goto cleanup;
						}
						break;

						default:
							/* TODO: unknown TLV found. Either
							 * 1) Warn user and skip TLV
							 * 2) Copy TLV (maybe warn user)
							 * 3) Abort extending with an error
							 */
						break;
					}
				break;

				default:
					/* TODO: unknown file header found. */
				break;
			}
		} else {
			if (logksi->ftlv_len > 0) {
				res = KT_INVALID_INPUT_FORMAT;
				ERR_CATCH_MSG(err, res, "Error: Block no. %zu: incomplete data found in log signature file.", logksi->blockNo);
			} else {
				break;
			}
		}
	}

	if (logksi->file.version == RECSIG11 || logksi->file.version == RECSIG12) {
		char strT1[256];

		logksi->file.nofTotalRecordHashes += logksi->block.nofRecordHashes;

		print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, " * %-*s%zu\n", SIZE_OF_LONG_INDENTATION, "Record count:", logksi->block.nofRecordHashes);

										if (logksi->block.recTimeMin > 0) {
									print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, " * %-*s%s\n", SIZE_OF_LONG_INDENTATION, "First record time:", LOGKSI_uint64_toDateString(logksi->block.recTimeMin, strT1, sizeof(strT1)));
								}

								if (logksi->block.recTimeMax > 0) {
									print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, " * %-*s%s\n", SIZE_OF_LONG_INDENTATION, "Last record time:", LOGKSI_uint64_toDateString(logksi->block.recTimeMax, strT1, sizeof(strT1)));
									print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, " * %-*s%s\n", SIZE_OF_LONG_INDENTATION, "Block duration:", time_diff_to_string(logksi->block.recTimeMax - logksi->block.recTimeMin, strT1, sizeof(strT1)));
								}
										print_debug_mp(mp, MP_ID_BLOCK_SUMMARY, DEBUG_EQUAL | DEBUG_LEVEL_2, "\n", SIZE_OF_LONG_INDENTATION, "Record count:", logksi->block.nofRecordHashes);

	}

	if (MULTI_PRINTER_hasDataByID(mp, MP_ID_BLOCK_PARSING_TREE_NODES)) {
		print_debug_mp(mp, MP_ID_BLOCK_PARSING_TREE_NODES, DEBUG_LEVEL_3, "}\n");
		MULTI_PRINTER_printByID(mp, MP_ID_BLOCK_PARSING_TREE_NODES);
	}


	/* If requested, return last leaf of last block. */
	if (lastLeaf != NULL) {
		KSI_DataHash_free(prevLeaf);
		prevLeaf = NULL;

		res = MERKLE_TREE_getPrevLeaf(logksi->tree, &prevLeaf);
		ERR_CATCH_MSG(err, res, "Error: Unable to get previous leaf.");

		*lastLeaf = KSI_DataHash_ref(prevLeaf);
	}

	if (last_rec_time != NULL) {
		*last_rec_time = logksi->block.recTimeMax;
	}

	res = finalize_log_signature(set, mp, err, logksi, files, ksi, theFirstInputHashInFile);
	if (res != KT_OK) goto cleanup;

	if (logksi->task.verify.errSignTime) {
		res = KT_VERIFICATION_FAILURE;
		ERR_TRCKR_ADD(err, res, "Error: Log block has signing time more recent than consecutive block!");
		goto cleanup;
	}

	res = KT_OK;

cleanup:

	if (logksi->quietError != KT_OK) {
		int isContinued = logksi->isContinuedOnFail && (res != KT_INVALID_CMD_PARAM) && (res != KT_USER_INPUT_FAILURE);
		res = logksi->quietError;
		ERR_TRCKR_ADD(err, res, isContinued ? "Error: Verification FAILED but was continued for further analysis." : "Error: Verification FAILED and was stopped.");
	}

	print_progressResult(mp, MP_ID_BLOCK, DEBUG_LEVEL_2, res);

	if (MULTI_PRINTER_hasDataByID(mp, MP_ID_BLOCK_ERRORS)) {
		print_debug_mp(mp, MP_ID_BLOCK_ERRORS, DEBUG_SMALLER | DEBUG_LEVEL_3, "\n");
	}

	MULTI_PRINTER_printByID(mp, MP_ID_BLOCK);
	MULTI_PRINTER_printByID(mp, MP_ID_BLOCK_ERRORS);

	KSI_DataHash_free(prevLeaf);
	REGEXP_free(tmp_regxp);
	KSI_DataHash_free(theFirstInputHashInFile);
	lastSignatureTime = logksi->block.sigTime_1;
	LOGKSI_freeAndClearInternals(logksi);

	return res;
}

int logsignature_extract(PARAM_SET *set, MULTI_PRINTER* mp, ERR_TRCKR *err, KSI_CTX *ksi, IO_FILES *files) {
	int res;
	LOGKSI logksi;
	unsigned char ftlv_raw[SOF_FTLV_BUFFER];
	SIGNATURE_PROCESSORS processors;
	KSI_DataHash *theFirstInputHashInFile = NULL;
	char *range = NULL;

	if (set == NULL || err == NULL || ksi == NULL || files == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	LOGKSI_initialize(&logksi);
	logksi.ftlv_raw = ftlv_raw;
	logksi.taskId = TASK_EXTRACT;
	logksi.err = err;
	memset(&processors, 0, sizeof(processors));
	processors.extract_signature = 1;

	res = MERKLE_TREE_new(&logksi.tree);
	if (res != KT_OK) goto cleanup;

	res = MERKLE_TREE_setCallbacks(logksi.tree, &logksi, logksi_extract_record_chain, logksi_new_record_chain);
	if (res != KT_OK) goto cleanup;


	logksi.isContinuedOnFail = PARAM_SET_isSetByName(set, "continue-on-fail");

	/* Initialize the first extract position. */
	res = PARAM_SET_getStr(set, "r", NULL, PST_PRIORITY_HIGHEST, PST_INDEX_LAST, (char**)&range);
	if (res != KT_OK) goto cleanup;

	if (range) {
		res = EXTRACT_INFO_new(range, &logksi.task.extract.info);
		if (res != KT_OK) goto cleanup;
	}

	res = process_magic_number(set, mp, err, &logksi, files);
	if (res != KT_OK) goto cleanup;

	if (logksi.file.version == RECSIG11 || logksi.file.version == RECSIG12) {
		res = KT_VERIFICATION_SKIPPED;
		ERR_TRCKR_ADD(err, res, "Extracting from excerpt file not possible! Only log signature file can be extracted to produce excerpt file.");
		goto cleanup;
	}

	while (!SMART_FILE_isEof(files->files.inSig)) {
		MULTI_PRINTER_printByID(mp, MP_ID_BLOCK);

		res = LOGKSI_FTLV_smartFileRead(files->files.inSig, logksi.ftlv_raw, SOF_FTLV_BUFFER, &logksi.ftlv_len, &logksi.ftlv);
		if (res == KSI_OK) {
			switch (logksi.ftlv.tag) {
				case 0x901:
					if (theFirstInputHashInFile == NULL) theFirstInputHashInFile = KSI_DataHash_ref(logksi.block.inputHash);
				case 0x902:
				case 0x903:
				case 0x911:
				case 0x904:
					res = process_log_signature_with_block_signature(set, mp, err, &logksi, files, ksi, &processors, NULL);
					if (res != KT_OK) goto cleanup;
				break;

				default:
					/* TODO: unknown TLV found. Either
					 * 1) Warn user and skip TLV
					 * 2) Copy TLV (maybe warn user)
					 * 3) Abort extending with an error
					 */
				break;
			}
		} else {
			if (logksi.ftlv_len > 0) {
				res = KT_INVALID_INPUT_FORMAT;
				ERR_CATCH_MSG(err, res, "Error: Block no. %zu: incomplete data found in log signature file.", logksi.blockNo);
			} else {
				break;
			}
		}
	}

	res = finalize_log_signature(set, mp, err, &logksi, files, ksi, theFirstInputHashInFile);
	if (res != KT_OK) goto cleanup;

	res = KT_OK;

cleanup:

	LOGKSI_freeAndClearInternals(&logksi);
	KSI_DataHash_free(theFirstInputHashInFile);

	return res;
}

int logsignature_integrate(PARAM_SET *set, MULTI_PRINTER* mp, ERR_TRCKR *err, KSI_CTX *ksi, LOGKSI* logksi, IO_FILES *files) {
	int res;
	unsigned char ftlv_raw[SOF_FTLV_BUFFER];
	SIGNATURE_PROCESSORS processors;
	KSI_DataHash *theFirstInputHashInFile = NULL;


	if (err == NULL || ksi == NULL || files == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	logksi->ftlv_raw = ftlv_raw;
	logksi->taskId = TASK_INTEGRATE;
	logksi->err = err;
	memset(&processors, 0, sizeof(processors));

	res = MERKLE_TREE_new(&logksi->tree);
	if (res != KT_OK) goto cleanup;

	logksi->isContinuedOnFail = PARAM_SET_isSetByName(set, "continue-on-fail");

	res = process_magic_number(set, mp, err, logksi, files);
	if (res != KT_OK) goto cleanup;

	while (!SMART_FILE_isEof(files->files.partsBlk)) {
		MULTI_PRINTER_printByID(mp, MP_ID_BLOCK);

		res = LOGKSI_FTLV_smartFileRead(files->files.partsBlk, logksi->ftlv_raw, SOF_FTLV_BUFFER, &logksi->ftlv_len, &logksi->ftlv);
		if (res == KSI_OK) {
			switch (logksi->ftlv.tag) {
				case 0x901:
					if (theFirstInputHashInFile == NULL) theFirstInputHashInFile = KSI_DataHash_ref(logksi->block.inputHash);
				case 0x902:
				case 0x903:
				case 0x911:
					res = process_log_signature(set, mp, err, logksi, files, ksi);
					if (res != KT_OK) goto cleanup;
				break;
				case 0x904:
				{
					print_progressDesc(mp, MP_ID_BLOCK, 0, DEBUG_EQUAL | DEBUG_LEVEL_2, "Integrating block no. %3zu: into log signature... ", logksi->blockNo);

					res = process_partial_block(set, mp, err, logksi, files, ksi);
					if (res != KT_OK) goto cleanup;

					res = LOGKSI_FTLV_smartFileRead(files->files.partsSig, logksi->ftlv_raw, SOF_FTLV_BUFFER, &logksi->ftlv_len, &logksi->ftlv);

					if (res != KT_OK) {
						if (logksi->ftlv_len > 0) {
							res = KT_INVALID_INPUT_FORMAT;
							ERR_TRCKR_ADD(err, res, "Error: Block no. %zu: incomplete data found in signatures file.", logksi->blockNo);
							ERR_CATCH_MSG(err, res, "Error: Block no. %zu: unable to parse KSI signature in signatures file.", logksi->blockNo);
						} else {
							res = KT_INVALID_INPUT_FORMAT;
							ERR_TRCKR_ADD(err, res, "Error: Block no. %zu: unexpected end of signatures file.", logksi->blockNo);
							ERR_CATCH_MSG(err, res, "Error: Block no. %zu: unable to parse KSI signature in signatures file.", logksi->blockNo);
						}
					}
					if (logksi->ftlv.tag != 0x904) {
						res = KT_INVALID_INPUT_FORMAT;
						ERR_TRCKR_ADD(err, res, "Error: Block no. %zu: unexpected TLV %04X read from block-signatures file.", logksi->blockNo, logksi->ftlv.tag);
						ERR_CATCH_MSG(err, res, "Error: Block no. %zu: unable to parse KSI signature in signatures file.", logksi->blockNo);
					}

					res = process_partial_signature(set, mp, err, logksi, files, ksi, &processors, 0);
					if (res != KT_OK) goto cleanup;
					print_progressResult(mp, MP_ID_BLOCK, DEBUG_EQUAL | DEBUG_LEVEL_2, res);
				}
				break;

				default:
					/* TODO: unknown TLV found. Either
					 * 1) Warn user and skip TLV
					 * 2) Copy TLV (maybe warn user)
					 * 3) Abort extending with an error
					 */
				break;
			}
		} else {
			if (logksi->ftlv_len > 0) {
				res = KT_INVALID_INPUT_FORMAT;
				ERR_CATCH_MSG(err, res, "Error: Block no. %zu: incomplete data found in blocks file.", logksi->blockNo);
			} else {
				break;
			}
		}
	}

	res = finalize_log_signature(set, mp, err, logksi, files, ksi, theFirstInputHashInFile);
	if (res != KT_OK) goto cleanup;

	res = KT_OK;

cleanup:

	print_progressResult(mp, MP_ID_BLOCK, DEBUG_EQUAL | DEBUG_LEVEL_2, res);
	KSI_DataHash_free(theFirstInputHashInFile);

	return res;
}

int logsignature_sign(PARAM_SET *set, MULTI_PRINTER* mp, ERR_TRCKR *err, KSI_CTX *ksi, IO_FILES *files) {
	int res;
	int progress;
	LOGKSI logksi;
	unsigned char ftlv_raw[SOF_FTLV_BUFFER];
	SIGNATURE_PROCESSORS processors;
	KSI_DataHash *theFirstInputHashInFile = NULL;
	int lastError = KT_OK;

	if (set == NULL || err == NULL || ksi == NULL || files == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	LOGKSI_initialize(&logksi);
	logksi.ftlv_raw = ftlv_raw;
	logksi.taskId = TASK_SIGN;
	logksi.err = err;
	memset(&processors, 0, sizeof(processors));
	processors.create_signature = wrapper_LOGKSI_createSignature;

	res = MERKLE_TREE_new(&logksi.tree);
	if (res != KT_OK) goto cleanup;

	logksi.isContinuedOnFail = PARAM_SET_isSetByName(set, "continue-on-fail");

	res = process_magic_number(set, mp, err, &logksi, files);
	if (res != KT_OK) goto cleanup;

	if (logksi.file.version == RECSIG11 || logksi.file.version == RECSIG12) {
		res = KT_VERIFICATION_SKIPPED;
		ERR_TRCKR_ADD(err, res, "Signing of excerpt file not possible! Only log signature file can be signed.");
		goto cleanup;
	}

	if (SMART_FILE_isStream(files->files.inSig)) {
		progress = (PARAM_SET_isSetByName(set, "d")&& PARAM_SET_isSetByName(set, "show-progress"));
	} else {
		/* Impossible to estimate signing progress if input is from stdin. */
		progress = 0;
	}

	if (progress) {
		res = count_blocks(err, ksi, &logksi, files->files.inSig);
		if (res != KT_OK) goto cleanup;
		print_debug("Progress: %3zu of %3zu blocks need signing. Estimated signing time: %3zu seconds.\n",
			logksi.task.sign.noSigCount,
			logksi.task.sign.blockCount,
			logksi.task.sign.noSigCount);
	}

	while (!SMART_FILE_isEof(files->files.inSig)) {
		MULTI_PRINTER_printByID(mp, MP_ID_BLOCK);

		res = LOGKSI_FTLV_smartFileRead(files->files.inSig, logksi.ftlv_raw, SOF_FTLV_BUFFER, &logksi.ftlv_len, &logksi.ftlv);
		if (res == KSI_OK) {
			switch (logksi.ftlv.tag) {
				case 0x901:
					if (theFirstInputHashInFile == NULL) theFirstInputHashInFile = KSI_DataHash_ref(logksi.block.inputHash);
				case 0x902:
				case 0x903:
				case 0x911:
					res = process_log_signature(set, mp, err, &logksi, files, ksi);
					if (res != KT_OK) goto cleanup;
				break;

				case 0x904:
				{
					res = process_partial_signature(set, mp, err, &logksi, files, ksi, &processors, progress);
					if (res == KT_SIGNING_FAILURE) {
						lastError = res;
						res = KT_OK;
					}

					if (res != KT_OK) goto cleanup;
				}
				break;

				default:
					/* TODO: unknown TLV found. Either
					 * 1) Warn user and skip TLV
					 * 2) Copy TLV (maybe warn user)
					 * 3) Abort extending with an error
					 */
				break;
			}
		} else {
			if (logksi.ftlv_len > 0) {
				res = KT_INVALID_INPUT_FORMAT;
				ERR_CATCH_MSG(err, res, "Error: Block no. %zu: incomplete data found in log signature file.", logksi.blockNo);
			} else {
				break;
			}
		}
	}

	res = finalize_log_signature(set, mp, err, &logksi, files, ksi, theFirstInputHashInFile);
	if (res != KT_OK) goto cleanup;

	res = SMART_FILE_markConsistent(files->files.outSig);
	ERR_CATCH_MSG(err, res, "Error: Could not close output log signature file %s.", files->internal.outSig);

	res = KT_OK;

cleanup:
	/**
	 * + If there is error mark output file as inconsistent.
	 * + If there is no changes and output is not explicitly specified
	 *   and output file already exists, mark output file as inconsistent.
	 * + Inconsistent state discards temporary file created.
	 */
	if (files->files.outSig != NULL &&
										(res != KT_OK ||
										 (!logksi.task.sign.outSigModified && !PARAM_SET_isSetByName(set, "o") && SMART_FILE_doFileExist(files->internal.outSig))
										)) {
		int tmp_res;
		tmp_res = SMART_FILE_markInconsistent(files->files.outSig);
		ERR_CATCH_MSG(err, tmp_res, "Error: Unable to mark output signature file as inconsistent.");
	}

	if (lastError != KT_OK) {
		res = lastError;
		ERR_TRCKR_ADD(err, res, "Error: Signing FAILED but was continued. All failed blocks are left unsigned!");
	}

	print_progressResult(mp, MP_ID_BLOCK, DEBUG_EQUAL | DEBUG_LEVEL_2, res);
	LOGKSI_freeAndClearInternals(&logksi);
	KSI_DataHash_free(theFirstInputHashInFile);

	return res;
}




static int count_blocks(ERR_TRCKR *err, KSI_CTX *ksi, LOGKSI *logksi, SMART_FILE *in) {
	int res;
	KSI_TlvElement *tlv = NULL;
	KSI_TlvElement *tlvNoSig = NULL;

	if (err == NULL || in == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	/* Do not count records, if input comes from stdin. */
	if (SMART_FILE_isStream(in)) {
		res = KT_OK;
		goto cleanup;
	}

	logksi->task.sign.blockCount = 0;
	logksi->task.sign.noSigCount = 0;
	logksi->task.sign.noSigNo = 0;

	while (!SMART_FILE_isEof(in)) {
		res = LOGKSI_FTLV_smartFileRead(in, logksi->ftlv_raw, SOF_FTLV_BUFFER, &logksi->ftlv_len, &logksi->ftlv);
		if (res == KSI_OK) {
			switch (logksi->ftlv.tag) {
				case 0x901:
					logksi->task.sign.blockCount++;
				break;

				case 0x904:
					res = tlv_element_parse_and_check_sub_elements(err, ksi, logksi->ftlv_raw, logksi->ftlv_len, logksi->ftlv.hdr_len, &tlv);
					ERR_CATCH_MSG(err, res, "Error: Block no. %zu: unable to parse block signature as TLV element.", logksi->blockNo);
					res = KSI_TlvElement_getElement(tlv, 0x02, &tlvNoSig);
					ERR_CATCH_MSG(err, res, "Error: Block no. %zu: unable to extract 'no-sig' element in signatures file.", logksi->blockNo);

					if (tlvNoSig) logksi->task.sign.noSigCount++;

					KSI_TlvElement_free(tlvNoSig);
					tlvNoSig = NULL;
					KSI_TlvElement_free(tlv);
					tlv = NULL;
				break;

				default:
				/* Ignore hashes and other TLVs as we are just counting blocks. */
				break;
			}
		} else {
			if (logksi->ftlv_len > 0) {
				res = KT_INVALID_INPUT_FORMAT;
				ERR_CATCH_MSG(err, res, "Error: Block no. %zu: incomplete data found in log signature file.", logksi->blockNo);
			} else {
				break;
			}
		}
	}

	res = KT_OK;

cleanup:

	if (in != NULL) SMART_FILE_rewind(in);

	KSI_TlvElement_free(tlvNoSig);
	KSI_TlvElement_free(tlv);

	return res;
}

static int skip_current_block_as_it_does_not_verify(LOGKSI *logksi, MULTI_PRINTER* mp, IO_FILES *files, ERR_TRCKR *err, KSI_CTX *ksi, int *skip) {
	int res = KT_UNKNOWN_ERROR;
	KSI_TlvElement *tlv = NULL;
	size_t i = 0;
	char buf[1024];
	size_t logLinesToSkip = 0;


	if (logksi == NULL || ksi == NULL ||  skip == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	/* If skipping is not enabled, just exit. */
	if ((*skip) == 0) {
		res = KT_OK;
		goto cleanup;
	}

	switch (logksi->ftlv.tag) {
		case 0x901:
			*skip = 0;

			/* Normally this is incremented in process_block_signature or process_partial_signature.
			   If this has not happened it must be incremented here. */
			if (logksi->block.firstLineNo - 1 == logksi->file.nofTotalRecordHashes) {
				logksi->file.nofTotalRecordHashes += logksi->block.recordCount;
			}

			logLinesToSkip = logksi->block.recordCount - (logksi->block.nofRecordHashes - logksi->block.nofMetaRecords);

			if (logLinesToSkip > 0) {
				print_debug_mp(mp, MP_ID_BLOCK, DEBUG_LEVEL_3, "Block no. %3zu: Skipping %zu log lines.\n", logksi->blockNo, logLinesToSkip);

				for (i = 0; i < logLinesToSkip; i++) {
					res = SMART_FILE_gets(files->files.inLog, buf, sizeof(buf), NULL);
					if (res != SMART_FILE_OK) goto cleanup;
				}
			}
		break;

		case 0x904:
			res = tlv_element_parse_and_check_sub_elements(err, ksi, logksi->ftlv_raw, logksi->ftlv_len, logksi->ftlv.hdr_len, &tlv);
			ERR_CATCH_MSG(err, res, "Error: Block no. %zu: unable to parse block signature as TLV element.", logksi->blockNo);

			res = tlv_element_get_uint(tlv, ksi, 0x01, &logksi->block.recordCount);
			ERR_CATCH_MSG(err, res, "Error: Block no. %zu: missing record count in block signature.", logksi->blockNo);
			logksi->sigNo++;
		break;
	}

	res = KT_OK;

cleanup:

	KSI_TlvElement_free(tlv);

	return res;
}

static int wrapper_LOGKSI_createSignature(PARAM_SET *set, MULTI_PRINTER *mp, ERR_TRCKR *err, KSI_CTX *ksi, LOGKSI *logksi, IO_FILES *files, KSI_DataHash *hash, KSI_uint64_t rootLevel, KSI_Signature **sig) {
	int res = KT_UNKNOWN_ERROR;
	int noErrTrckr = 0;

	if (set == NULL || err == NULL || ksi == NULL || logksi == NULL || files == NULL || hash == NULL || sig == NULL) {
		return KT_INVALID_ARGUMENT;
	}

	/* If --continue-on-fail is set, do not add errors to ERR_TRCKR as the amount of errors
	   will easily exceed its limits. */
	noErrTrckr = logksi->isContinuedOnFail;

	print_progressDesc(mp, MP_ID_BLOCK, 1, DEBUG_EQUAL | DEBUG_LEVEL_2, "Signing Block no. %3zu... ", logksi->blockNo);
	res = LOGKSI_createSignature((noErrTrckr ? NULL : err), ksi, hash, rootLevel, sig);
	print_progressResult(mp, MP_ID_BLOCK, DEBUG_EQUAL | DEBUG_LEVEL_2, res);

	return res;
}

static int logksi_set_extract_record(LOGKSI *logksi, RECORD_INFO *recordInfo, int isMetaRecordHash, KSI_DataHash *hash) {
	int res = KT_UNKNOWN_ERROR;
	KSI_DataHash *hashRef = NULL;
	char *logLineCopy = NULL;


	if (logksi == NULL || recordInfo == NULL || hash == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	hashRef = KSI_DataHash_ref(hash);
	if (hashRef == NULL) {
		res = KT_OUT_OF_MEMORY;
		goto cleanup;
	}

	if (isMetaRecordHash) {
		res = RECORD_INFO_setMetaRecordHash(recordInfo,
			EXTRACT_INFO_getNextPosition(logksi->task.extract.info),
			logksi->block.nofRecordHashes,
			hashRef,
			logksi->task.extract.metaRecord, logksi->task.extract.metaRecord_len);
		if (res != KT_OK) goto cleanup;
		hashRef = NULL;
	} else {
		res = KSI_strdup(logksi->logLine, &logLineCopy);
		if (res != KT_OK) goto cleanup;

		res = RECORD_INFO_setRecordHash(recordInfo,
			EXTRACT_INFO_getNextPosition(logksi->task.extract.info),
			logksi->block.nofRecordHashes,
			hashRef, logLineCopy);
		if (res != KT_OK) goto cleanup;

		hashRef = NULL;
		logLineCopy = NULL;
	}

	res = KT_OK;

cleanup:

	KSI_DataHash_free(hashRef);
	free(logLineCopy);

	return res;
}

/* MERKLE_TREE newRecordChain implementation. */
static int logksi_new_record_chain(MERKLE_TREE *tree, void *ctx, int isMetaRecordHash, KSI_DataHash *hash) {
	int res;
	LOGKSI *logksi = ctx;
	ERR_TRCKR *err = NULL;
	KSI_DataHash *hshRef = NULL;
	KSI_DataHash *prevMask = NULL;
	char *logLineCopy = NULL;

	if (tree == NULL || ctx == NULL || hash == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	err = logksi->err;

	/*
	 * Enter only if not all extract positions are found AND
	 * current record hash is at desired position.
	 */
	if (EXTRACT_INFO_isLastPosPending(logksi->task.extract.info) &&
		EXTRACT_INFO_getNextPosition(logksi->task.extract.info) - logksi->file.nofTotalRecordHashes == logksi->block.nofRecordHashes) {
		RECORD_INFO *recordInfo = NULL;
		size_t index = 0;

		hshRef = KSI_DataHash_ref(hash);
		if (hshRef == NULL) {
			res = KT_OUT_OF_MEMORY;
			ERR_CATCH_MSG(err, res, "Error: Unable to create hash reference.");
		}

		/* Get reference to record info. */
		res = EXTRACT_INFO_getNewRecord(logksi->task.extract.info, &index, &recordInfo);
		ERR_CATCH_MSG(err, res, "Error: Unable to create new extract info extractor.");

		res = logksi_set_extract_record(logksi, recordInfo, isMetaRecordHash, hash);
		if (isMetaRecordHash) {
			ERR_CATCH_MSG(err, res, "Error: Unable to create new extract record for metadata.");
		} else {
			ERR_CATCH_MSG(err, res, "Error: Unable to create new extract record for record.");
		}

		/* Retreive and use mask. */
		res = MERKLE_TREE_getPrevMask(tree, &prevMask);
		if (res != KT_OK) goto cleanup;

		if (isMetaRecordHash) {
			res = RECORD_INFO_add_hash_to_record_chain(recordInfo, LEFT_LINK, prevMask, 0);
		} else {
			res = RECORD_INFO_add_hash_to_record_chain(recordInfo, RIGHT_LINK, prevMask, 0);
		}
		if (res != KT_OK) goto cleanup;

		res = EXTRACT_INFO_moveToNext(logksi->task.extract.info);
		ERR_CATCH_MSG(err, res, "Error: Unable to move to next extract position.");
	}


	res = KT_OK;

cleanup:

	KSI_DataHash_free(hshRef);
	KSI_DataHash_free(prevMask);
	free(logLineCopy);

	return res;
}

/* MERKLE_TREE extractRecordChain implementation. */
static int logksi_extract_record_chain(MERKLE_TREE *tree, void *ctx, unsigned char level, KSI_DataHash *leftLink) {
	int res;
	size_t j;
	int condition;
	LOGKSI *logksi = ctx;
	ERR_TRCKR *err = NULL;
	KSI_DataHash *hsh = NULL;
	int finalize;

	if (ctx == NULL || leftLink == NULL) {
		res = KT_INVALID_ARGUMENT;
		goto cleanup;
	}

	err = logksi->err;
	finalize = MERKLE_TREE_isClosing(tree);

	/**
	 * The input hash will represent the root value of the leftmost subtree that
	 * has level. The root value is compared with extract info and its suitability
	 * for extract hash chain node is examined. If value is suitable it is included
	 * to the chain.
	 */
	for (j = 0; j < EXTRACT_INFO_getPositionsInBlock(logksi->task.extract.info); j++) {
		RECORD_INFO *record = NULL;
		size_t recordOffset = 0;
		size_t recordLevel = 0;

		res = EXTRACT_INFO_getRecord(logksi->task.extract.info, j, &record);
		ERR_CATCH_MSG(err, res, "Error: Block no. %zu: unable to get extract record.", logksi->blockNo);

		res = RECORD_INFO_getPositionInTree(record, &recordOffset, &recordLevel);
		ERR_CATCH_MSG(err, res, "Error: Block no. %zu: unable get extract record position in tree.", logksi->blockNo);

		/**
		 * Check that the (level + 1) matches with extractLevel (expected next level).
		 * If the level is less it is not suitable for building extract chain.
		 */
		if (finalize) {
			condition = (level + 1 >= recordLevel);
		} else {
			condition = (level + 1 == recordLevel);
		}
		if (condition) {
			if (((recordOffset - 1) >> level) & 1L) {
				res = MERKLE_TREE_get(logksi->tree, level, &hsh);
				ERR_CATCH_MSG(err, res, "Error: Block no. %zu: unable get hash from merkle tree.", logksi->blockNo);

				res = RECORD_INFO_add_hash_to_record_chain(record, RIGHT_LINK, hsh, level + 1 - recordLevel);
			} else {
				res = RECORD_INFO_add_hash_to_record_chain(record, LEFT_LINK, leftLink, level + 1 - recordLevel);
			}
			if (res != KT_OK) {
				ERR_CATCH_MSG(err, res, "Error: Unable to add hash to record chain.");
				goto cleanup;
			}

			KSI_DataHash_free(hsh);
			hsh = NULL;
		}
	}

	res = KT_OK;

cleanup:

	KSI_DataHash_free(hsh);

	return res;
}

