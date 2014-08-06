module vibe.core.events.types;
package:

enum L1CACHE_ALLOC = 512-1;
enum LOG = true;

import std.typecons: Flag;
alias isIPv6 = Flag!"IPv6";
alias isTCP = Flag!"TCP";
alias isForced = Flag!"ForceFind";


struct StatusInfo {
	Status code = Status.OK;
	string text;
}

enum TCPEvent : char {
	ERROR = 0,
	CONNECT,
	READ, 
	WRITE,
	CLOSE
}

enum TCPOptions : char {
	NODELAY = 0,		// Don't delay send to coalesce packets
	CORK,
	LINGER,
	BUFFER_RECV,
	BUFFER_SEND,
	TIMEOUT_RECV,
	TIMEOUT_SEND,
	TIMEOUT_HALFOPEN,
	KEEPALIVE_ENABLE,
	KEEPALIVE_DEFER,	// Start keeplives after this period
	KEEPALIVE_COUNT,	// Number of keepalives before death
	KEEPALIVE_INTERVAL,	// Interval between keepalives
	DEFER_ACCEPT,
	QUICK_ACK,			// Bock/reenable quick ACKs.
	CONGESTION
}

enum Status : char {
	OK					=	0,
	ASYNC				=	1,
	RETRY				=	2,
	ERROR				=	3,
	ABORT				=	4,
	EVLOOP_TIMEOUT		=	5,
	EVLOOP_FAILURE		=	6,
	NOT_IMPLEMENTED		=	7
}

enum EWIN : size_t {
	ERROR_SUCCESS							=	0,
	NO_ERROR								=	0,
	ERROR_INVALID_FUNCTION					=	1,
	ERROR_FILE_NOT_FOUND					=	2,
	ERROR_PATH_NOT_FOUND					=	3,
	ERROR_TOO_MANY_OPEN_FILES				=	4,
	ERROR_ACCESS_DENIED						=	5,
	ERROR_INVALID_HANDLE					=	6,
	ERROR_ARENA_TRASHED						=	7,
	ERROR_NOT_ENOUGH_MEMORY					=	8,
	ERROR_INVALID_BLOCK						=	9,
	ERROR_BAD_ENVIRONMENT					=	10,
	ERROR_BAD_FORMAT						=	11,
	ERROR_INVALID_ACCESS					=	12,
	ERROR_INVALID_DATA						=	13,
	ERROR_OUTOFMEMORY						=	14,
	ERROR_INVALID_DRIVE						=	15,
	ERROR_CURRENT_DIRECTORY					=	16,
	ERROR_NOT_SAME_DEVICE					=	17,
	ERROR_NO_MORE_FILES						=	18,
	ERROR_WRITE_PROTECT						=	19,
	ERROR_BAD_UNIT							=	20,
	ERROR_NOT_READY							=	21,
	ERROR_BAD_COMMAND						=	22,
	ERROR_CRC								=	23,
	ERROR_BAD_LENGTH						=	24,
	ERROR_SEEK								=	25,
	ERROR_NOT_DOS_DISK						=	26,
	ERROR_SECTOR_NOT_FOUND					=	27,
	ERROR_OUT_OF_PAPER						=	28,
	ERROR_WRITE_FAULT						=	29,
	ERROR_READ_FAULT						=	30,
	ERROR_GEN_FAILURE						=	31,
	ERROR_SHARING_VIOLATION					=	32,
	ERROR_LOCK_VIOLATION					=	33,
	ERROR_WRONG_DISK						=	34,
	ERROR_SHARING_BUFFER_EXCEEDED			=	36,
	ERROR_HANDLE_EOF						=	38,
	ERROR_HANDLE_DISK_FULL					=	39,
	ERROR_NOT_SUPPORTED						=	50,
	ERROR_REM_NOT_LIST						=	51,
	ERROR_DUP_NAME							=	52,
	ERROR_BAD_NETPATH						=	53,
	ERROR_NETWORK_BUSY						=	54,
	ERROR_DEV_NOT_EXIST						=	55,
	ERROR_TOO_MANY_CMDS						=	56,
	ERROR_ADAP_HDW_ERR						=	57,
	ERROR_BAD_NET_RESP						=	58,
	ERROR_UNEXP_NET_ERR						=	59,
	ERROR_BAD_REM_ADAP						=	60,
	ERROR_PRINTQ_FULL						=	61,
	ERROR_NO_SPOOL_SPACE					=	62,
	ERROR_PRINT_CANCELLED					=	63,
	ERROR_NETNAME_DELETED					=	64,
	ERROR_NETWORK_ACCESS_DENIED				=	65,
	ERROR_BAD_DEV_TYPE						=	66,
	ERROR_BAD_NET_NAME						=	67,
	ERROR_TOO_MANY_NAMES					=	68,
	ERROR_TOO_MANY_SESS						=	69,
	ERROR_SHARING_PAUSED					=	70,
	ERROR_REQ_NOT_ACCEP						=	71,
	ERROR_REDIR_PAUSED						=	72,
	ERROR_FILE_EXISTS						=	80,
	ERROR_CANNOT_MAKE						=	82,
	ERROR_FAIL_I24							=	83,
	ERROR_OUT_OF_STRUCTURES					=	84,
	ERROR_ALREADY_ASSIGNED					=	85,
	ERROR_INVALID_PASSWORD					=	86,
	ERROR_INVALID_PARAMETER					=	87,
	ERROR_NET_WRITE_FAULT					=	88,
	ERROR_NO_PROC_SLOTS						=	89,
	ERROR_TOO_MANY_SEMAPHORES				=	100,
	ERROR_EXCL_SEM_ALREADY_OWNED			=	101,
	ERROR_SEM_IS_SET						=	102,
	ERROR_TOO_MANY_SEM_REQUESTS				=	103,
	ERROR_INVALID_AT_INTERRUPT_TIME			=	104,
	ERROR_SEM_OWNER_DIED					=	105,
	ERROR_SEM_USER_LIMIT					=	106,
	ERROR_DISK_CHANGE						=	107,
	ERROR_DRIVE_LOCKED						=	108,
	ERROR_BROKEN_PIPE						=	109,
	ERROR_OPEN_FAILED						=	110,
	ERROR_BUFFER_OVERFLOW					=	111,
	ERROR_DISK_FULL							=	112,
	ERROR_NO_MORE_SEARCH_HANDLES			=	113,
	ERROR_INVALID_TARGET_HANDLE				=	114,
	ERROR_INVALID_CATEGORY					=	117,
	ERROR_INVALID_VERIFY_SWITCH				=	118,
	ERROR_BAD_DRIVER_LEVEL					=	119,
	ERROR_CALL_NOT_IMPLEMENTED				=	120,
	ERROR_SEM_TIMEOUT						=	121,
	ERROR_INSUFFICIENT_BUFFER				=	122,
	ERROR_INVALID_NAME						=	123,
	ERROR_INVALID_LEVEL						=	124,
	ERROR_NO_VOLUME_LABEL					=	125,
	ERROR_MOD_NOT_FOUND						=	126,
	ERROR_PROC_NOT_FOUND					=	127,
	ERROR_WAIT_NO_CHILDREN					=	128,
	ERROR_CHILD_NOT_COMPLETE				=	129,
	ERROR_DIRECT_ACCESS_HANDLE				=	130,
	ERROR_NEGATIVE_SEEK						=	131,
	ERROR_SEEK_ON_DEVICE					=	132,
	ERROR_IS_JOIN_TARGET					=	133,
	ERROR_IS_JOINED							=	134,
	ERROR_IS_SUBSTED						=	135,
	ERROR_NOT_JOINED						=	136,
	ERROR_NOT_SUBSTED						=	137,
	ERROR_JOIN_TO_JOIN						=	138,
	ERROR_SUBST_TO_SUBST					=	139,
	ERROR_JOIN_TO_SUBST						=	140,
	ERROR_SUBST_TO_JOIN						=	141,
	ERROR_BUSY_DRIVE						=	142,
	ERROR_SAME_DRIVE						=	143,
	ERROR_DIR_NOT_ROOT						=	144,
	ERROR_DIR_NOT_EMPTY						=	145,
	ERROR_IS_SUBST_PATH						=	146,
	ERROR_IS_JOIN_PATH						=	147,
	ERROR_PATH_BUSY							=	148,
	ERROR_IS_SUBST_TARGET					=	149,
	ERROR_SYSTEM_TRACE						=	150,
	ERROR_INVALID_EVENT_COUNT				=	151,
	ERROR_TOO_MANY_MUXWAITERS				=	152,
	ERROR_INVALID_LIST_FORMAT				=	153,
	ERROR_LABEL_TOO_LONG					=	154,
	ERROR_TOO_MANY_TCBS						=	155,
	ERROR_SIGNAL_REFUSED					=	156,
	ERROR_DISCARDED							=	157,
	ERROR_NOT_LOCKED						=	158,
	ERROR_BAD_THREADID_ADDR					=	159,
	ERROR_BAD_ARGUMENTS						=	160,
	ERROR_BAD_PATHNAME						=	161,
	ERROR_SIGNAL_PENDING					=	162,
	ERROR_MAX_THRDS_REACHED					=	164,
	ERROR_LOCK_FAILED						=	167,/*
	ERROR_BUSY								=	170,
	ERROR_CANCEL_VIOLATION					=	173,
	ERROR_ATOMIC_LOCKS_NOT_SUPPORTED		=	174,
	ERROR_INVALID_SEGMENT_NUMBER			=	180,
	ERROR_INVALID_ORDINAL					=	182,
	ERROR_ALREADY_EXISTS					=	183,
	ERROR_INVALID_FLAG_NUMBER				=	186,
	ERROR_SEM_NOT_FOUND						=	187,
	ERROR_INVALID_STARTING_CODESEG			=	188,
	ERROR_INVALID_STACKSEG					=	189,
	ERROR_INVALID_MODULETYPE				=	190,
	ERROR_INVALID_EXE_SIGNATURE				=	191,
	ERROR_EXE_MARKED_INVALID				=	192,
	ERROR_BAD_EXE_FORMAT					=	193,
	ERROR_ITERATED_DATA_EXCEEDS_64k			=	194,
	ERROR_INVALID_MINALLOCSIZE				=	195,
	ERROR_DYNLINK_FROM_INVALID_RING			=	196,
	ERROR_IOPL_NOT_ENABLED					=	197,
	ERROR_INVALID_SEGDPL					=	198,
	ERROR_AUTODATASEG_EXCEEDS_64k			=	199,
	ERROR_RING2SEG_MUST_BE_MOVABLE			=	200,
	ERROR_RELOC_CHAIN_XEEDS_SEGLIM			=	201,
	ERROR_INFLOOP_IN_RELOC_CHAIN			=	202,
	ERROR_ENVVAR_NOT_FOUND					=	203,
	ERROR_NO_SIGNAL_SENT					=	205,
	ERROR_FILENAME_EXCED_RANGE				=	206,
	ERROR_RING2_STACK_IN_USE				=	207,
	ERROR_META_EXPANSION_TOO_LONG			=	208,
	ERROR_INVALID_SIGNAL_NUMBER				=	209,
	ERROR_THREAD_1_INACTIVE					=	210,
	ERROR_LOCKED							=	212,
	ERROR_TOO_MANY_MODULES					=	214,
	ERROR_NESTING_NOT_ALLOWED				=	215,
	ERROR_BAD_PIPE							=	230,
	ERROR_PIPE_BUSY							=	231,
	ERROR_NO_DATA							=	232,
	ERROR_PIPE_NOT_CONNECTED				=	233,
	ERROR_MORE_DATA							=	234,
	ERROR_VC_DISCONNECTED					=	240,
	ERROR_INVALID_EA_NAME					=	254,
	ERROR_EA_LIST_INCONSISTENT				=	255,
	ERROR_NO_MORE_ITEMS						=	259,
	ERROR_CANNOT_COPY						=	266,
	ERROR_DIRECTORY							=	267,
	ERROR_EAS_DIDNT_FIT						=	275,
	ERROR_EA_FILE_CORRUPT					=	276,
	ERROR_EA_TABLE_FULL						=	277,
	ERROR_INVALID_EA_HANDLE					=	278,
	ERROR_EAS_NOT_SUPPORTED					=	282,
	ERROR_NOT_OWNER							=	288,
	ERROR_TOO_MANY_POSTS					=	298,
	ERROR_PARTIAL_COPY						=	299,
	ERROR_MR_MID_NOT_FOUND					=	317,
	ERROR_INVALID_ADDRESS					=	487,
	ERROR_ARITHMETIC_OVERFLOW				=	534,
	ERROR_PIPE_CONNECTED					=	535,
	ERROR_PIPE_LISTENING					=	536,
	ERROR_EA_ACCESS_DENIED					=	994,
	ERROR_OPERATION_ABORTED					=	995,
	ERROR_IO_INCOMPLETE						=	996,
	ERROR_IO_PENDING						=	997,
	ERROR_NOACCESS							=	998,
	ERROR_SWAPERROR							=	999,
	ERROR_STACK_OVERFLOW					=	1001,
	ERROR_INVALID_MESSAGE					=	1002,
	ERROR_CAN_NOT_COMPLETE					=	1003,
	ERROR_INVALID_FLAGS						=	1004,
	ERROR_UNRECOGNIZED_VOLUME				=	1005,
	ERROR_FILE_INVALID						=	1006,
	ERROR_FULLSCREEN_MODE					=	1007,
	ERROR_NO_TOKEN							=	1008,
	ERROR_BADDB								=	1009,
	ERROR_BADKEY							=	1010,
	ERROR_CANTOPEN							=	1011,
	ERROR_CANTREAD							=	1012,
	ERROR_CANTWRITE							=	1013,
	ERROR_REGISTRY_RECOVERED				=	1014,
	ERROR_REGISTRY_CORRUPT					=	1015,
	ERROR_REGISTRY_IO_FAILED				=	1016,
	ERROR_NOT_REGISTRY_FILE					=	1017,
	ERROR_KEY_DELETED						=	1018,
	ERROR_NO_LOG_SPACE						=	1019,
	ERROR_KEY_HAS_CHILDREN					=	1020,
	ERROR_CHILD_MUST_BE_VOLATILE			=	1021,
	ERROR_NOTIFY_ENUM_DIR					=	1022,
	ERROR_DEPENDENT_SERVICES_RUNNING		=	1051,
	ERROR_INVALID_SERVICE_CONTROL			=	1052,
	ERROR_SERVICE_REQUEST_TIMEOUT			=	1053,
	ERROR_SERVICE_NO_THREAD					=	1054,
	ERROR_SERVICE_DATABASE_LOCKED			=	1055,
	ERROR_SERVICE_ALREADY_RUNNING			=	1056,
	ERROR_INVALID_SERVICE_ACCOUNT			=	1057,
	ERROR_SERVICE_DISABLED					=	1058,
	ERROR_CIRCULAR_DEPENDENCY				=	1059,
	ERROR_SERVICE_DOES_NOT_EXIST			=	1060,
	ERROR_SERVICE_CANNOT_ACCEPT_CTRL		=	1061,
	ERROR_SERVICE_NOT_ACTIVE				=	1062,
	ERROR_FAILED_SERVICE_CONTROLLER_CONNECT	=	1063,
	ERROR_EXCEPTION_IN_SERVICE				=	1064,
	ERROR_DATABASE_DOES_NOT_EXIST			=	1065,
	ERROR_SERVICE_SPECIFIC_ERROR			=	1066,
	ERROR_PROCESS_ABORTED					=	1067,
	ERROR_SERVICE_DEPENDENCY_FAIL			=	1068,
	ERROR_SERVICE_LOGON_FAILED				=	1069,
	ERROR_SERVICE_START_HANG				=	1070,
	ERROR_INVALID_SERVICE_LOCK				=	1071,
	ERROR_SERVICE_MARKED_FOR_DELETE			=	1072,
	ERROR_SERVICE_EXISTS					=	1073,
	ERROR_ALREADY_RUNNING_LKG				=	1074,
	ERROR_SERVICE_DEPENDENCY_DELETED		=	1075,
	ERROR_BOOT_ALREADY_ACCEPTED				=	1076,
	ERROR_SERVICE_NEVER_STARTED				=	1077,
	ERROR_DUPLICATE_SERVICE_NAME			=	1078,
	ERROR_END_OF_MEDIA						=	1100,
	ERROR_FILEMARK_DETECTED					=	1101,
	ERROR_BEGINNING_OF_MEDIA				=	1102,
	ERROR_SETMARK_DETECTED					=	1103,
	ERROR_NO_DATA_DETECTED					=	1104,
	ERROR_PARTITION_FAILURE					=	1105,
	ERROR_INVALID_BLOCK_LENGTH				=	1106,
	ERROR_DEVICE_NOT_PARTITIONED			=	1107,
	ERROR_UNABLE_TO_LOCK_MEDIA				=	1108,
	ERROR_UNABLE_TO_UNLOAD_MEDIA			=	1109,
	ERROR_MEDIA_CHANGED						=	1110,
	ERROR_BUS_RESET							=	1111,
	ERROR_NO_MEDIA_IN_DRIVE					=	1112,
	ERROR_NO_UNICODE_TRANSLATION			=	1113,
	ERROR_DLL_INIT_FAILED					=	1114,
	ERROR_SHUTDOWN_IN_PROGRESS				=	1115,
	ERROR_NO_SHUTDOWN_IN_PROGRESS			=	1116,
	ERROR_IO_DEVICE							=	1117,
	ERROR_SERIAL_NO_DEVICE					=	1118,
	ERROR_IRQ_BUSY							=	1119,
	ERROR_MORE_WRITES						=	1120,
	ERROR_COUNTER_TIMEOUT					=	1121,
	ERROR_FLOPPY_ID_MARK_NOT_FOUND			=	1122,
	ERROR_FLOPPY_WRONG_CYLINDER				=	1123,
	ERROR_FLOPPY_UNKNOWN_ERROR				=	1124,
	ERROR_FLOPPY_BAD_REGISTERS				=	1125,
	ERROR_DISK_RECALIBRATE_FAILED			=	1126,
	ERROR_DISK_OPERATION_FAILED				=	1127,
	ERROR_DISK_RESET_FAILED					=	1128,
	ERROR_EOM_OVERFLOW						=	1129,
	ERROR_NOT_ENOUGH_SERVER_MEMORY			=	1130,
	ERROR_POSSIBLE_DEADLOCK					=	1131,
	ERROR_MAPPED_ALIGNMENT					=	1132,
	ERROR_SET_POWER_STATE_VETOED			=	1140,
	ERROR_SET_POWER_STATE_FAILED			=	1141,
	ERROR_TOO_MANY_LINKS					=	1142,
	ERROR_OLD_WIN_VERSION					=	1150,
	ERROR_APP_WRONG_OS						=	1151,
	ERROR_SINGLE_INSTANCE_APP				=	1152,
	ERROR_RMODE_APP							=	1153,
	ERROR_INVALID_DLL						=	1154,
	ERROR_NO_ASSOCIATION					=	1155,
	ERROR_DDE_FAIL							=	1156,
	ERROR_DLL_NOT_FOUND						=	1157,
	ERROR_BAD_USERNAME						=	2202,
	ERROR_NOT_CONNECTED						=	2250,
	ERROR_OPEN_FILES						=	2401,
	ERROR_ACTIVE_CONNECTIONS				=	2402,
	ERROR_DEVICE_IN_USE						=	2404,
	ERROR_BAD_DEVICE						=	1200,
	ERROR_CONNECTION_UNAVAIL				=	1201,
	ERROR_DEVICE_ALREADY_REMEMBERED			=	1202,
	ERROR_NO_NET_OR_BAD_PATH				=	1203,
	ERROR_BAD_PROVIDER						=	1204,
	ERROR_CANNOT_OPEN_PROFILE				=	1205,
	ERROR_BAD_PROFILE						=	1206,
	ERROR_NOT_CONTAINER						=	1207,
	ERROR_EXTENDED_ERROR					=	1208,
	ERROR_INVALID_GROUPNAME					=	1209,
	ERROR_INVALID_COMPUTERNAME				=	1210,
	ERROR_INVALID_EVENTNAME					=	1211,
	ERROR_INVALID_DOMAINNAME				=	1212,
	ERROR_INVALID_SERVICENAME				=	1213,
	ERROR_INVALID_NETNAME					=	1214,
	ERROR_INVALID_SHARENAME					=	1215,
	ERROR_INVALID_PASSWORDNAME				=	1216,
	ERROR_INVALID_MESSAGENAME				=	1217,
	ERROR_INVALID_MESSAGEDEST				=	1218,
	ERROR_SESSION_CREDENTIAL_CONFLICT		=	1219,
	ERROR_REMOTE_SESSION_LIMIT_EXCEEDED		=	1220,
	ERROR_DUP_DOMAINNAME					=	1221,
	ERROR_NO_NETWORK						=	1222,
	ERROR_CANCELLED							=	1223,
	ERROR_USER_MAPPED_FILE					=	1224,
	ERROR_CONNECTION_REFUSED				=	1225,
	ERROR_GRACEFUL_DISCONNECT				=	1226,
	ERROR_ADDRESS_ALREADY_ASSOCIATED		=	1227,
	ERROR_ADDRESS_NOT_ASSOCIATED			=	1228,
	ERROR_CONNECTION_INVALID				=	1229,
	ERROR_CONNECTION_ACTIVE					=	1230,
	ERROR_NETWORK_UNREACHABLE				=	1231,
	ERROR_HOST_UNREACHABLE					=	1232,
	ERROR_PROTOCOL_UNREACHABLE				=	1233,
	ERROR_PORT_UNREACHABLE					=	1234,
	ERROR_REQUEST_ABORTED					=	1235,
	ERROR_CONNECTION_ABORTED				=	1236,
	ERROR_RETRY								=	1237,
	ERROR_CONNECTION_COUNT_LIMIT			=	1238,
	ERROR_LOGIN_TIME_RESTRICTION			=	1239,
	ERROR_LOGIN_WKSTA_RESTRICTION			=	1240,
	ERROR_INCORRECT_ADDRESS					=	1241,
	ERROR_ALREADY_REGISTERED				=	1242,
	ERROR_SERVICE_NOT_FOUND					=	1243,
	ERROR_NOT_AUTHENTICATED					=	1244,
	ERROR_NOT_LOGGED_ON						=	1245,
	ERROR_CONTINUE							=	1246,
	ERROR_ALREADY_INITIALIZED				=	1247,
	ERROR_NO_MORE_DEVICES					=	1248,
	ERROR_NOT_ALL_ASSIGNED					=	1300,
	ERROR_SOME_NOT_MAPPED					=	1301,
	ERROR_NO_QUOTAS_FOR_ACCOUNT				=	1302,
	ERROR_LOCAL_USER_SESSION_KEY			=	1303,
	ERROR_NULL_LM_PASSWORD					=	1304,
	ERROR_UNKNOWN_REVISION					=	1305,
	ERROR_REVISION_MISMATCH					=	1306,
	ERROR_INVALID_OWNER						=	1307,
	ERROR_INVALID_PRIMARY_GROUP				=	1308,
	ERROR_NO_IMPERSONATION_TOKEN			=	1309,
	ERROR_CANT_DISABLE_MANDATORY			=	1310,
	ERROR_NO_LOGON_SERVERS					=	1311,
	ERROR_NO_SUCH_LOGON_SESSION				=	1312,
	ERROR_NO_SUCH_PRIVILEGE					=	1313,
	ERROR_PRIVILEGE_NOT_HELD				=	1314,
	ERROR_INVALID_ACCOUNT_NAME				=	1315,
	ERROR_USER_EXISTS						=	1316,
	ERROR_NO_SUCH_USER						=	1317,
	ERROR_GROUP_EXISTS						=	1318,
	ERROR_NO_SUCH_GROUP						=	1319,
	ERROR_MEMBER_IN_GROUP					=	1320,
	ERROR_MEMBER_NOT_IN_GROUP				=	1321,
	ERROR_LAST_ADMIN						=	1322,
	ERROR_WRONG_PASSWORD					=	1323,
	ERROR_ILL_FORMED_PASSWORD				=	1324,
	ERROR_PASSWORD_RESTRICTION				=	1325,
	ERROR_LOGON_FAILURE						=	1326,
	ERROR_ACCOUNT_RESTRICTION				=	1327,
	ERROR_INVALID_LOGON_HOURS				=	1328,
	ERROR_INVALID_WORKSTATION				=	1329,
	ERROR_PASSWORD_EXPIRED					=	1330,
	ERROR_ACCOUNT_DISABLED					=	1331,
	ERROR_NONE_MAPPED						=	1332,
	ERROR_TOO_MANY_LUIDS_REQUESTED			=	1333,
	ERROR_LUIDS_EXHAUSTED					=	1334,
	ERROR_INVALID_SUB_AUTHORITY				=	1335,
	ERROR_INVALID_ACL						=	1336,
	ERROR_INVALID_SID						=	1337,
	ERROR_INVALID_SECURITY_DESCR			=	1338,
	ERROR_BAD_INHERITANCE_ACL				=	1340,
	ERROR_SERVER_DISABLED					=	1341,
	ERROR_SERVER_NOT_DISABLED				=	1342,
	ERROR_INVALID_ID_AUTHORITY				=	1343,
	ERROR_ALLOTTED_SPACE_EXCEEDED			=	1344,
	ERROR_INVALID_GROUP_ATTRIBUTES			=	1345,
	ERROR_BAD_IMPERSONATION_LEVEL			=	1346,
	ERROR_CANT_OPEN_ANONYMOUS				=	1347,
	ERROR_BAD_VALIDATION_CLASS				=	1348,
	ERROR_BAD_TOKEN_TYPE					=	1349,
	ERROR_NO_SECURITY_ON_OBJECT				=	1350,
	ERROR_CANT_ACCESS_DOMAIN_INFO			=	1351,
	ERROR_INVALID_SERVER_STATE				=	1352,
	ERROR_INVALID_DOMAIN_STATE				=	1353,
	ERROR_INVALID_DOMAIN_ROLE				=	1354,
	ERROR_NO_SUCH_DOMAIN					=	1355,
	ERROR_DOMAIN_EXISTS						=	1356,
	ERROR_DOMAIN_LIMIT_EXCEEDED				=	1357,
	ERROR_INTERNAL_DB_CORRUPTION			=	1358,
	ERROR_INTERNAL_ERROR					=	1359,
	ERROR_GENERIC_NOT_MAPPED				=	1360,
	ERROR_BAD_DESCRIPTOR_FORMAT				=	1361,
	ERROR_NOT_LOGON_PROCESS					=	1362,
	ERROR_LOGON_SESSION_EXISTS				=	1363,
	ERROR_NO_SUCH_PACKAGE					=	1364,
	ERROR_BAD_LOGON_SESSION_STATE			=	1365,
	ERROR_LOGON_SESSION_COLLISION			=	1366,
	ERROR_INVALID_LOGON_TYPE				=	1367,
	ERROR_CANNOT_IMPERSONATE				=	1368,
	ERROR_RXACT_INVALID_STATE				=	1369,
	ERROR_RXACT_COMMIT_FAILURE				=	1370,
	ERROR_SPECIAL_ACCOUNT					=	1371,
	ERROR_SPECIAL_GROUP						=	1372,
	ERROR_SPECIAL_USER						=	1373,
	ERROR_MEMBERS_PRIMARY_GROUP				=	1374,
	ERROR_TOKEN_ALREADY_IN_USE				=	1375,
	ERROR_NO_SUCH_ALIAS						=	1376,
	ERROR_MEMBER_NOT_IN_ALIAS				=	1377,
	ERROR_MEMBER_IN_ALIAS					=	1378,
	ERROR_ALIAS_EXISTS						=	1379,
	ERROR_LOGON_NOT_GRANTED					=	1380,
	ERROR_TOO_MANY_SECRETS					=	1381,
	ERROR_SECRET_TOO_LONG					=	1382,
	ERROR_INTERNAL_DB_ERROR					=	1383,
	ERROR_TOO_MANY_CONTEXT_IDS				=	1384,
	ERROR_LOGON_TYPE_NOT_GRANTED			=	1385,
	ERROR_NT_CROSS_ENCRYPTION_REQUIRED		=	1386,
	ERROR_NO_SUCH_MEMBER					=	1387,
	ERROR_INVALID_MEMBER					=	1388,
	ERROR_TOO_MANY_SIDS						=	1389,
	ERROR_LM_CROSS_ENCRYPTION_REQUIRED		=	1390,
	ERROR_NO_INHERITANCE					=	1391,
	ERROR_FILE_CORRUPT						=	1392,
	ERROR_DISK_CORRUPT						=	1393,
	ERROR_NO_USER_SESSION_KEY				=	1394,
	ERROR_LICENSE_QUOTA_EXCEEDED			=	1395,
	ERROR_INVALID_WINDOW_HANDLE				=	1400,
	ERROR_INVALID_MENU_HANDLE				=	1401,
	ERROR_INVALID_CURSOR_HANDLE				=	1402,
	ERROR_INVALID_ACCEL_HANDLE				=	1403,
	ERROR_INVALID_HOOK_HANDLE				=	1404,
	ERROR_INVALID_DWP_HANDLE				=	1405,
	ERROR_TLW_WITH_WSCHILD					=	1406,
	ERROR_CANNOT_FIND_WND_CLASS				=	1407,
	ERROR_WINDOW_OF_OTHER_THREAD			=	1408,
	ERROR_HOTKEY_ALREADY_REGISTERED			=	1409,
	ERROR_CLASS_ALREADY_EXISTS				=	1410,
	ERROR_CLASS_DOES_NOT_EXIST				=	1411,
	ERROR_CLASS_HAS_WINDOWS					=	1412,
	ERROR_INVALID_INDEX						=	1413,
	ERROR_INVALID_ICON_HANDLE				=	1414,
	ERROR_PRIVATE_DIALOG_INDEX				=	1415,
	ERROR_LISTBOX_ID_NOT_FOUND				=	1416,
	ERROR_NO_WILDCARD_CHARACTERS			=	1417,
	ERROR_CLIPBOARD_NOT_OPEN				=	1418,
	ERROR_HOTKEY_NOT_REGISTERED				=	1419,
	ERROR_WINDOW_NOT_DIALOG					=	1420,
	ERROR_CONTROL_ID_NOT_FOUND				=	1421,
	ERROR_INVALID_COMBOBOX_MESSAGE			=	1422,
	ERROR_WINDOW_NOT_COMBOBOX				=	1423,
	ERROR_INVALID_EDIT_HEIGHT				=	1424,
	ERROR_DC_NOT_FOUND						=	1425,
	ERROR_INVALID_HOOK_FILTER				=	1426,
	ERROR_INVALID_FILTER_PROC				=	1427,
	ERROR_HOOK_NEEDS_HMOD					=	1428,
	ERROR_GLOBAL_ONLY_HOOK					=	1429,
	ERROR_JOURNAL_HOOK_SET					=	1430,
	ERROR_HOOK_NOT_INSTALLED				=	1431,
	ERROR_INVALID_LB_MESSAGE				=	1432,
	ERROR_SETCOUNT_ON_BAD_LB				=	1433,
	ERROR_LB_WITHOUT_TABSTOPS				=	1434,
	ERROR_DESTROY_OBJECT_OF_OTHER_THREAD	=	1435,
	ERROR_CHILD_WINDOW_MENU					=	1436,
	ERROR_NO_SYSTEM_MENU					=	1437,
	ERROR_INVALID_MSGBOX_STYLE				=	1438,
	ERROR_INVALID_SPI_VALUE					=	1439,
	ERROR_SCREEN_ALREADY_LOCKED				=	1440,
	ERROR_HWNDS_HAVE_DIFF_PARENT			=	1441,
	ERROR_NOT_CHILD_WINDOW					=	1442,
	ERROR_INVALID_GW_COMMAND				=	1443,
	ERROR_INVALID_THREAD_ID					=	1444,
	ERROR_NON_MDICHILD_WINDOW				=	1445,
	ERROR_POPUP_ALREADY_ACTIVE				=	1446,
	ERROR_NO_SCROLLBARS						=	1447,
	ERROR_INVALID_SCROLLBAR_RANGE			=	1448,
	ERROR_INVALID_SHOWWIN_COMMAND			=	1449,
	ERROR_NO_SYSTEM_RESOURCES				=	1450,
	ERROR_NONPAGED_SYSTEM_RESOURCES			=	1451,
	ERROR_PAGED_SYSTEM_RESOURCES			=	1452,
	ERROR_WORKING_SET_QUOTA					=	1453,
	ERROR_PAGEFILE_QUOTA					=	1454,
	ERROR_COMMITMENT_LIMIT					=	1455,
	ERROR_MENU_ITEM_NOT_FOUND				=	1456,
	ERROR_EVENTLOG_FILE_CORRUPT				=	1500,
	ERROR_EVENTLOG_CANT_START				=	1501,
	ERROR_LOG_FILE_FULL						=	1502,
	ERROR_EVENTLOG_FILE_CHANGED				=	1503,
	RPC_S_INVALID_STRING_BINDING			=	1700,
	RPC_S_WRONG_KIND_OF_BINDING				=	1701,
	RPC_S_INVALID_BINDING					=	1702,
	RPC_S_PROTSEQ_NOT_SUPPORTED				=	1703,
	RPC_S_INVALID_RPC_PROTSEQ				=	1704,
	RPC_S_INVALID_STRING_UUID				=	1705,
	RPC_S_INVALID_ENDPOINT_FORMAT			=	1706,
	RPC_S_INVALID_NET_ADDR					=	1707,
	RPC_S_NO_ENDPOINT_FOUND					=	1708,
	RPC_S_INVALID_TIMEOUT					=	1709,
	RPC_S_OBJECT_NOT_FOUND					=	1710,
	RPC_S_ALREADY_REGISTERED				=	1711,
	RPC_S_TYPE_ALREADY_REGISTERED			=	1712,
	RPC_S_ALREADY_LISTENING					=	1713,
	RPC_S_NO_PROTSEQS_REGISTERED			=	1714,
	RPC_S_NOT_LISTENING						=	1715,
	RPC_S_UNKNOWN_MGR_TYPE					=	1716,
	RPC_S_UNKNOWN_IF						=	1717,
	RPC_S_NO_BINDINGS						=	1718,
	RPC_S_NO_PROTSEQS						=	1719,
	RPC_S_CANT_CREATE_ENDPOINT				=	1720,
	RPC_S_OUT_OF_RESOURCES					=	1721,
	RPC_S_SERVER_UNAVAILABLE				=	1722,
	RPC_S_SERVER_TOO_BUSY					=	1723,
	RPC_S_INVALID_NETWORK_OPTIONS			=	1724,
	RPC_S_NO_CALL_ACTIVE					=	1725,
	RPC_S_CALL_FAILED						=	1726,
	RPC_S_CALL_FAILED_DNE					=	1727,
	RPC_S_PROTOCOL_ERROR					=	1728,
	RPC_S_UNSUPPORTED_TRANS_SYN				=	1730,
	RPC_S_UNSUPPORTED_TYPE					=	1732,
	RPC_S_INVALID_TAG						=	1733,
	RPC_S_INVALID_BOUND						=	1734,
	RPC_S_NO_ENTRY_NAME						=	1735,
	RPC_S_INVALID_NAME_SYNTAX				=	1736,
	RPC_S_UNSUPPORTED_NAME_SYNTAX			=	1737,
	RPC_S_UUID_NO_ADDRESS					=	1739,
	RPC_S_DUPLICATE_ENDPOINT				=	1740,
	RPC_S_UNKNOWN_AUTHN_TYPE				=	1741,
	RPC_S_MAX_CALLS_TOO_SMALL				=	1742,
	RPC_S_STRING_TOO_LONG					=	1743,
	RPC_S_PROTSEQ_NOT_FOUND					=	1744,
	RPC_S_PROCNUM_OUT_OF_RANGE				=	1745,
	RPC_S_BINDING_HAS_NO_AUTH				=	1746,
	RPC_S_UNKNOWN_AUTHN_SERVICE				=	1747,
	RPC_S_UNKNOWN_AUTHN_LEVEL				=	1748,
	RPC_S_INVALID_AUTH_IDENTITY				=	1749,
	RPC_S_UNKNOWN_AUTHZ_SERVICE				=	1750,
	EPT_S_INVALID_ENTRY						=	1751,
	EPT_S_CANT_PERFORM_OP					=	1752,
	EPT_S_NOT_REGISTERED					=	1753,
	RPC_S_NOTHING_TO_EXPORT					=	1754,
	RPC_S_INCOMPLETE_NAME					=	1755,
	RPC_S_INVALID_VERS_OPTION				=	1756,
	RPC_S_NO_MORE_MEMBERS					=	1757,
	RPC_S_NOT_ALL_OBJS_UNEXPORTED			=	1758,
	RPC_S_INTERFACE_NOT_FOUND				=	1759,
	RPC_S_ENTRY_ALREADY_EXISTS				=	1760,
	RPC_S_ENTRY_NOT_FOUND					=	1761,
	RPC_S_NAME_SERVICE_UNAVAILABLE			=	1762,
	RPC_S_INVALID_NAF_ID					=	1763,
	RPC_S_CANNOT_SUPPORT					=	1764,
	RPC_S_NO_CONTEXT_AVAILABLE				=	1765,
	RPC_S_INTERNAL_ERROR					=	1766,
	RPC_S_ZERO_DIVIDE						=	1767,
	RPC_S_ADDRESS_ERROR						=	1768,
	RPC_S_FP_DIV_ZERO						=	1769,
	RPC_S_FP_UNDERFLOW						=	1770,
	RPC_S_FP_OVERFLOW						=	1771,
	RPC_X_NO_MORE_ENTRIES					=	1772,
	RPC_X_SS_CHAR_TRANS_OPEN_FAIL			=	1773,
	RPC_X_SS_CHAR_TRANS_SHORT_FILE			=	1774,
	RPC_X_SS_IN_NULL_CONTEXT				=	1775,
	RPC_X_SS_CONTEXT_DAMAGED				=	1777,
	RPC_X_SS_HANDLES_MISMATCH				=	1778,
	RPC_X_SS_CANNOT_GET_CALL_HANDLE			=	1779,
	RPC_X_NULL_REF_POINTER					=	1780,
	RPC_X_ENUM_VALUE_OUT_OF_RANGE			=	1781,
	RPC_X_BYTE_COUNT_TOO_SMALL				=	1782,
	RPC_X_BAD_STUB_DATA						=	1783,
	ERROR_INVALID_USER_BUFFER				=	1784,
	ERROR_UNRECOGNIZED_MEDIA				=	1785,
	ERROR_NO_TRUST_LSA_SECRET				=	1786,
	ERROR_NO_TRUST_SAM_ACCOUNT				=	1787,
	ERROR_TRUSTED_DOMAIN_FAILURE			=	1788,
	ERROR_TRUSTED_RELATIONSHIP_FAILURE		=	1789,
	ERROR_TRUST_FAILURE						=	1790,
	RPC_S_CALL_IN_PROGRESS					=	1791,
	ERROR_NETLOGON_NOT_STARTED				=	1792,
	ERROR_ACCOUNT_EXPIRED					=	1793,
	ERROR_REDIRECTOR_HAS_OPEN_HANDLES		=	1794,
	ERROR_PRINTER_DRIVER_ALREADY_INSTALLED	=	1795,
	ERROR_UNKNOWN_PORT						=	1796,
	ERROR_UNKNOWN_PRINTER_DRIVER			=	1797,
	ERROR_UNKNOWN_PRINTPROCESSOR			=	1798,
	ERROR_INVALID_SEPARATOR_FILE			=	1799,
	ERROR_INVALID_PRIORITY					=	1800,
	ERROR_INVALID_PRINTER_NAME				=	1801,
	ERROR_PRINTER_ALREADY_EXISTS			=	1802,
	ERROR_INVALID_PRINTER_COMMAND			=	1803,
	ERROR_INVALID_DATATYPE					=	1804,
	ERROR_INVALID_ENVIRONMENT				=	1805,
	RPC_S_NO_MORE_BINDINGS					=	1806,
	ERROR_NOLOGON_INTERDOMAIN_TRUST_ACCOUNT	=	1807,
	ERROR_NOLOGON_WORKSTATION_TRUST_ACCOUNT	=	1808,
	ERROR_NOLOGON_SERVER_TRUST_ACCOUNT		=	1809,
	ERROR_DOMAIN_TRUST_INCONSISTENT			=	1810,
	ERROR_SERVER_HAS_OPEN_HANDLES			=	1811,
	ERROR_RESOURCE_DATA_NOT_FOUND			=	1812,
	ERROR_RESOURCE_TYPE_NOT_FOUND			=	1813,
	ERROR_RESOURCE_NAME_NOT_FOUND			=	1814,
	ERROR_RESOURCE_LANG_NOT_FOUND			=	1815,
	ERROR_NOT_ENOUGH_QUOTA					=	1816,
	RPC_S_NO_INTERFACES						=	1817,
	RPC_S_CALL_CANCELLED					=	1818,
	RPC_S_BINDING_INCOMPLETE				=	1819,
	RPC_S_COMM_FAILURE						=	1820,
	RPC_S_UNSUPPORTED_AUTHN_LEVEL			=	1821,
	RPC_S_NO_PRINC_NAME						=	1822,
	RPC_S_NOT_RPC_ERROR						=	1823,
	RPC_S_UUID_LOCAL_ONLY					=	1824,
	RPC_S_SEC_PKG_ERROR						=	1825,
	RPC_S_NOT_CANCELLED						=	1826,
	RPC_X_INVALID_ES_ACTION					=	1827,
	RPC_X_WRONG_ES_VERSION					=	1828,
	RPC_X_WRONG_STUB_VERSION				=	1829,
	RPC_S_GROUP_MEMBER_NOT_FOUND			=	1898,
	EPT_S_CANT_CREATE						=	1899,
	RPC_S_INVALID_OBJECT					=	1900,
	ERROR_INVALID_TIME						=	1901,
	ERROR_INVALID_FORM_NAME					=	1902,
	ERROR_INVALID_FORM_SIZE					=	1903,
	ERROR_ALREADY_WAITING					=	1904,
	ERROR_PRINTER_DELETED					=	1905,
	ERROR_INVALID_PRINTER_STATE				=	1906,
	ERROR_PASSWORD_MUST_CHANGE				=	1907,
	ERROR_DOMAIN_CONTROLLER_NOT_FOUND		=	1908,
	ERROR_ACCOUNT_LOCKED_OUT				=	1909,
	ERROR_NO_BROWSER_SERVERS_FOUND			=	6118,
	ERROR_INVALID_PIXEL_FORMAT				=	2000,
	ERROR_BAD_DRIVER						=	2001,
	ERROR_INVALID_WINDOW_STYLE				=	2002,
	ERROR_METAFILE_NOT_SUPPORTED			=	2003,
	ERROR_TRANSFORM_NOT_SUPPORTED			=	2004,
	ERROR_CLIPPING_NOT_SUPPORTED			=	2005,
	ERROR_UNKNOWN_PRINT_MONITOR				=	3000,
	ERROR_PRINTER_DRIVER_IN_USE				=	3001,
	ERROR_SPOOL_FILE_NOT_FOUND				=	3002,
	ERROR_SPL_NO_STARTDOC					=	3003,
	ERROR_SPL_NO_ADDJOB						=	3004,
	ERROR_PRINT_PROCESSOR_ALREADY_INSTALLED	=	3005,
	ERROR_PRINT_MONITOR_ALREADY_INSTALLED	=	3006,
	ERROR_WINS_INTERNAL						=	4000,
	ERROR_CAN_NOT_DEL_LOCAL_WINS			=	4001,
	ERROR_STATIC_INIT						=	4002,
	ERROR_INC_BACKUP						=	4003,
	ERROR_FULL_BACKUP						=	4004,
	ERROR_REC_NON_EXISTENT					=	4005,
	ERROR_RPL_NOT_ALLOWED					=	4006,*/
	WSA_OK					=	0,		/* No error */
	WSA_INVALID_HANDLE		=	6,		/* Specified event object handle is invalid. */
	WSA_NOT_ENOUGH_MEMORY	= 	8,		/* Insufficient memory available. */
	WSA_INVALID_PARAMETER 	=	87,		/* One or more parameters are invalid. */
	WSA_OPERATION_ABORTED	=	995,	/* Overlapped operation aborted. */
	WSA_IO_INCOMPLETE		=	996,	/* Overlapped I/O event object not in signaled state. */
	WSA_IO_PENDING			=	997,	/* Overlapped operations will complete later. */
	WSAEINTR				=	10004,	/* Interrupted function call. */
	WSAEBADF				=	10009,	/* File handle is not valid. */
	WSAEACCES				=	10013,	/* Permission denied. */
	WSAEFAULT				=	10014,	/* Bad address. */
	WSAEINVAL				=	10022,	/* Invalid argument. */
	WSAEMFILE				=	10024,	/* Too many open files. */
	WSAEWOULDBLOCK			=	10035,	/* Resource temporarily unavailable. */
	WSAEINPROGRESS			=	10036,	/* Operation now in progress. */
	WSAEALREADY				=	10037,	/* Operation already in progress. */
	WSAENOTSOCK				=	10038,	/* Socket operation on nonsocket. */
	WSAEDESTADDRREQ			=	10039,	/* Destination address required. */
	WSAEMSGSIZE				=	10040,	/* Message too long. */
	WSAEPROTOTYPE			=	10041,	/* Protocol wrong type for socket. */
	WSAENOPROTOOPT			=	10042,	/* Bad protocol option. */
	WSAEPROTONOSUPPORT		=	10043,	/* Protocol not supported. */
	WSAESOCKTNOSUPPORT		=	10044,	/* Socket type not supported. */
	WSAEOPNOTSUPP			=	10045,	/* Operation not supported. */
	WSAEPFNOSUPPORT			=	10046,	/* Protocol family not supported. */
	WSAEAFNOSUPPORT			=	10047,	/* Address family not supported by protocol family. */
	WSAEADDRINUSE			=	10048,	/* Address already in use. */
	WSAEADDRNOTAVAIL		=	10049,	/* Cannot assign requested address. */
	WSAENETDOWN				=	10050,	/* Network is down. */
	WSAENETUNREACH			=	10051,	/* Network is unreachable. */
	WSAENETRESET			=	10052,	/* Network dropped connection on reset. */
	WSAECONNABORTED			=	10053,	/* Software caused connection abort. */
	WSAECONNRESET			=	10054,	/* Connection reset by peer. */
	WSAENOBUFS				=	10055,	/* No buffer space available. */
	WSAEISCONN				=	10056,	/* Socket is already connected. */
	WSAENOTCONN				=	10057,	/* Socket is not connected. */
	WSAESHUTDOWN			=	10058,	/* Cannot send after socket shutdown. */
	WSAETOOMANYREFS			=	10059,	/* Too many references. */
	WSAETIMEDOUT			=	10060,	/* Connection timed out. */
	WSAECONNREFUSED			=	10061,	/* Connection refused. */
	WSAELOOP				=	10062,	/* Cannot translate name. */
	WSAENAMETOOLONG			=	10063,	/* Name too long. */
	WSAEHOSTDOWN			=	10064,	/* Host is down. */
	WSAEHOSTUNREACH			=	10065,	/* No route to host. */
	WSAENOTEMPTY			=	10066,	/* Directory not empty. */
	WSAEPROCLIM				=	10067,	/* Too many processes. */
	WSAEUSERS				=	10068,	/* User quota exceeded. */
	WSAEDQUOT				=	10069,	/* Disk quota exceeded. */
	WSAESTALE				=	10070,	/* Stale file handle reference. */
	WSAEREMOTE				=	10071,	/* Item is remote. */
	WSASYSNOTREADY			=	10091,	/* Network subsystem is unavailable. */
	WSAVERNOTSUPPORTED		=	10092,	/* Winsock.dll version out of range. */
	WSANOTINITIALISED		=	10093,	/* Successful WSAStartup not yet performed. */
	WSAEDISCON				=	10101,	/* Graceful shutdown in progress. */
	WSAENOMORE				=	10102,	/* No more results. */
	WSAECANCELLED			=	10103,	/* Call has been canceled. */
	WSAEINVALIDPROCTABLE	=	10104,	/* Procedure call table is invalid. */
	WSAEINVALIDPROVIDER		=	10105,	/* Service provider is invalid. */
	WSAEPROVIDERFAILEDINIT	=	10106,	/* Service provider failed to initialize. */
	WSASYSCALLFAILURE		=	10107,	/* System call failure. */
	WSASERVICE_NOT_FOUND	=	10108,	/* Service not found. */
	WSATYPE_NOT_FOUND		=	10109,	/* Class type not found. */
	WSA_E_NO_MORE			=	10110,	/* No more results. */
	WSA_E_CANCELLED			=	10111,	/* Call was canceled. */
	WSAEREFUSED				=	10112,	/* Database query was refused. */
	WSAHOST_NOT_FOUND		=	11001,	/* Host not found. */
	WSATRY_AGAIN			=	11002,	/* Nonauthoritative host not found. */
	WSANO_RECOVERY			=	11003,	/* This is a nonrecoverable error. */
	WSANO_DATA				=	11004,	/* Valid name, no data record of requested type. */
	WSA_QOS_RECEIVERS		=	11005,	/* QOS receivers. */
	WSA_QOS_SENDERS			=	11006,	/* QOS senders. */
	WSA_QOS_NO_SENDERS		=	11007,	/* No QOS senders. */
	WSA_QOS_NO_RECEIVERS	=	11008,	/* QOS no receivers. */
	WSA_QOS_REQUEST_CONFIRMED	=	11009,	/* QOS request confirmed. */
	WSA_QOS_ADMISSION_FAILURE	=	11010,	/* QOS admission error. */
	WSA_QOS_POLICY_FAILURE		=	11011,	/* QOS policy failure. */
	WSA_QOS_BAD_STYLE			=	11012,	/* QOS bad style. */
	WSA_QOS_BAD_OBJECT			=	11013,	/* QOS bad object. */
	WSA_QOS_TRAFFIC_CTRL_ERROR	=	11014,	/* QOS traffic control error. */
	WSA_QOS_GENERIC_ERROR		=	11015,	/* QOS generic error. */
	WSA_QOS_ESERVICETYPE		=	11016,	/* QOS service type error. */
	WSA_QOS_EFLOWSPEC			=	11017,	/* QOS flowspec error. */
	WSA_QOS_EPROVSPECBUF		=	11018,	/* Invalid QOS provider buffer. */
	WSA_QOS_EFILTERSTYLE		=	11019,	/* Invalid QOS filter style. */
	WSA_QOS_EFILTERTYPE			=	11020,	/* Invalid QOS filter type. */
	WSA_QOS_EFILTERCOUNT		=	11021,	/* Incorrect QOS filter count. */
	WSA_QOS_EOBJLENGTH			=	11022,	/* Invalid QOS object length. */
	WSA_QOS_EFLOWCOUNT			=	11023,	/* Incorrect QOS flow count. */
	WSA_QOS_EUNKOWNPSOBJ		=	11024,	/* Unrecognized QOS object. */
	WSA_QOS_EPOLICYOBJ			=	11025,	/* Invalid QOS policy object. */
	WSA_QOS_EFLOWDESC			=	11026,	/* Invalid QOS flow descriptor. */
	WSA_QOS_EPSFLOWSPEC			=	11027,	/* Invalid QOS provider-specific flowspec. */
	WSA_QOS_EPSFILTERSPEC		=	11028,	/* Invalid QOS provider-specific filterspec. */
	WSA_QOS_ESDMODEOBJ			=	11029,	/* Invalid QOS shape discard mode object. */
	WSA_QOS_ESHAPERATEOBJ		=	11030,	/* Invalid QOS shaping rate object. */
	WSA_QOS_RESERVED_PETYPE		=	11031	/* Reserved policy QOS element type. */
}

enum EPosix : int {
	EAI_OVERFLOW	=		-12,	/* Argument buffer overflow.  */
	EAI_SYSTEM		=		-11,	/* System error returned in `errno'.  */
	EAI_MEMORY		=		-10,	/* Memory allocation failure.  */
	EAI_SERVICE		=		-8,		/* SERVICE not supported for `ai_socktype'.  */
	EAI_SOCKTYPE	=		-7,		/* `ai_socktype' not supported.  */
	EAI_FAMILY		=		-6,		/* `ai_family' not supported.  */
	EAI_FAIL		=		-4,		/* Non-recoverable failure in name res.  */
	EAI_AGAIN		=		-3,		/* Temporary failure in name resolution.  */
	EAI_NONAME		=		-2,		/* NAME or SERVICE is unknown.  */
	/*EAI_BADFLAGS	=		-1,    	Invalid value for `ai_flags' field.  */
	EINVALID		=		-1,
	EOK				=		0,
	EPERM			=		1,      /* Operation not permitted */
	ENOENT			=		2,      /* No such file or directory */
	ESRCH			=		3,      /* No such process */
	EINTR			=		4,      /* Interrupted system call */
	EIO				=		5,      /* I/O error */
	ENXIO			=		6,      /* No such device or address */
	E2BIG			=		7,      /* Argument list too long */
	ENOEXEC			=		8,      /* Exec format error */
	EBADF			=		9,      /* Bad file number */
	ECHILD			=		10,      /* No child processes */
	EAGAIN			=		11,      /* Try again */
	ENOMEM			=		12,      /* Out of memory */
	EACCES			=		13,      /* Permission denied */
	EFAULT			=		14,      /* Bad address */
	ENOTBLK			=		15,      /* Block device required */
	EBUSY			=		16,      /* Device or resource busy */
	EEXIST			=		17,      /* File exists */
	EXDEV			=		18,      /* Cross-device link */
	ENODEV			=		19,      /* No such device */
	ENOTDIR			=		20,      /* Not a directory */
	EISDIR			=		21,      /* Is a directory */
	EINVAL			=		22,      /* Invalid argument */
	ENFILE			=		23,      /* File table overflow */
	EMFILE			=		24,      /* Too many open files */
	ENOTTY			=		25,      /* Not a typewriter */
	ETXTBSY			=		26,      /* Text file busy */
	EFBIG			=		27,      /* File too large */
	ENOSPC			=		28,      /* No space left on device */
	ESPIPE			=		29,      /* Illegal seek */
	EROFS			=		30,      /* Read-only file system */
	EMLINK			=		31,      /* Too many links */
	EPIPE			=		32,      /* Broken pipe */
	EDOM			=		33,      /* Math argument out of domain of func */
	ERANGE			=		34,      /* Math result not representable */
	EDEADLK			=		35,      /* Resource deadlock would occur */
	ENAMETOOLONG	=		36,      /* File name too long */
	ENOLCK			=		37,      /* No record locks available */
	ENOSYS			=		38,      /* Function not implemented */
	ENOTEMPTY		=		39,      /* Directory not empty */
	ELOOP			=		40,      /* Too many symbolic links encountered */
	EWOULDBLOCK		=		EAGAIN,  /* Operation would block */
	ENOMSG			=		42,      /* No message of desired type */
	EIDRM			=		43,      /* Identifier removed */
	ECHRNG			=		44,      /* Channel number out of range */
	EL2NSYNC		=		45,      /* Level 2 not synchronized */
	EL3HLT			=		46,      /* Level 3 halted */
	EL3RST			=		47,      /* Level 3 reset */
	ELNRNG			=		48,      /* Link number out of range */
	EUNATCH			=		49,      /* Protocol driver not attached */
	ENOCSI			=		50,      /* No CSI structure available */
	EL2HLT			=		51,      /* Level 2 halted */
	EBADE			=		52,      /* Invalid exchange */
	EBADR			=		53,      /* Invalid request descriptor */
	EXFULL			=		54,      /* Exchange full */
	ENOANO			=		55,      /* No anode */
	EBADRQC			=		56,      /* Invalid request code */
	EBADSLT			=		57,      /* Invalid slot */
	EDEADLOCK		=		EDEADLK,
	EBFONT			=		59,      /* Bad font file format */
	ENOSTR			=		60,      /* Device not a stream */
	ENODATA			=		61,      /* No data available */
	ETIME			=		62,      /* Timer expired */
	ENOSR			=		63,      /* Out of streams resources */
	ENONET			=		64,      /* Machine is not on the network */
	ENOPKG			=		65,      /* Package not installed */
	EREMOTE			=		66,      /* Object is remote */
	ENOLINK			=		67,      /* Link has been severed */
	EADV			=		68,      /* Advertise error */
	ESRMNT			=		69,      /* Srmount error */
	ECOMM			=		70,      /* Communication error on send */
	EPROTO			=		71,      /* Protocol error */
	EMULTIHOP		=		72,      /* Multihop attempted */
	EDOTDOT			=		73,      /* RFS specific error */
	EBADMSG			=		74,      /* Not a data message */
	EOVERFLOW		=		75,      /* Value too large for defined data type */
	ENOTUNIQ		=		76,      /* Name not unique on network */
	EBADFD			=		77,      /* File descriptor in bad state */
	EREMCHG			=		78,      /* Remote address changed */
	ELIBACC			=		79,      /* Can not access a needed shared library */
	ELIBBAD			=		80,      /* Accessing a corrupted shared library */
	ELIBSCN			=		81,      /* .lib section in a.out corrupted */
	ELIBMAX			=		82,      /* Attempting to link in too many shared libraries */
	ELIBEXEC		=		83,      /* Cannot exec a shared library directly */
	EILSEQ			=		84,      /* Illegal byte sequence */
	ERESTART		=		85,      /* Interrupted system call should be restarted */
	ESTRPIPE		=		86,      /* Streams pipe error */
	EUSERS			=		87,      /* Too many users */
	ENOTSOCK		=		88,      /* Socket operation on non-socket */
	EDESTADDRREQ	=		89,      /* Destination address required */
	EMSGSIZE		=		90,      /* Message too long */
	EPROTOTYPE		=		91,      /* Protocol wrong type for socket */
	ENOPROTOOPT		=		92,      /* Protocol not available */
	EPROTONOSUPPORT	=		93,      /* Protocol not supported */
	ESOCKTNOSUPPORT	=		94,      /* Socket type not supported */
	EOPNOTSUPP		=		95,      /* Operation not supported on transport endpoint */
	EPFNOSUPPORT	=		96,      /* Protocol family not supported */
	EAFNOSUPPORT	=		97,      /* Address family not supported by protocol */
	EADDRINUSE		=		98,      /* Address already in use */
	EADDRNOTAVAIL	=		99,      /* Cannot assign requested address */
	ENETDOWN		=		100,     /* Network is down */
	ENETUNREACH		=		101,     /* Network is unreachable */
	ENETRESET		=		102,     /* Network dropped connection because of reset */
	ECONNABORTED	=		103,     /* Software caused connection abort */
	ECONNRESET		=		104,     /* Connection reset by peer */
	ENOBUFS			=		105,     /* No buffer space available */
	EISCONN			=		106,     /* Transport endpoint is already connected */
	ENOTCONN		=		107,     /* Transport endpoint is not connected */
	ESHUTDOWN		=		108,     /* Cannot send after transport endpoint shutdown */
	ETOOMANYREFS	=		109,     /* Too many references: cannot splice */
	ETIMEDOUT		=		110,     /* Connection timed out */
	ECONNREFUSED	=		111,     /* Connection refused */
	EHOSTDOWN		=		112,     /* Host is down */
	EHOSTUNREACH	=		113,     /* No route to host */
	EALREADY		=		114,     /* Operation already in progress */
	EINPROGRESS		=		115,     /* Operation now in progress */
	ESTALE			=		116,     /* Stale file handle */
	EUCLEAN			=		117,     /* Structure needs cleaning */
	ENOTNAM			=		118,     /* Not a XENIX named type file */
	ENAVAIL			=		119,     /* No XENIX semaphores available */
	EISNAM			=		120,     /* Is a named type file */
	EREMOTEIO		=		121,     /* Remote I/O error */
	EDQUOT			=		122,     /* Quota exceeded */
	ENOMEDIUM		=		123,     /* No medium found */
	EMEDIUMTYPE		=		124,     /* Wrong medium type */
	ECANCELED		=		125,     /* Operation Canceled */
	ENOKEY			=		126,     /* Required key not available */
	EKEYEXPIRED		=		127,     /* Key has expired */
	EKEYREVOKED		=		128,     /* Key has been revoked */
	EKEYREJECTED	=		129,     /* Key was rejected by service */
	/* for robust mutexes */
	EOWNERDEAD		=		130,     /* Owner died */
	ENOTRECOVERABLE	=		131,     /* State not recoverable */
	ERFKILL			=		132,     /* Operation not possible due to RF-kill */
	EHWPOISON		=		133     /* Memory page has hardware error */
}

string[EWIN] EWSAMessages;
string[EPosix] EPosixMessages;

static this() {
	with (EWIN){
		EWSAMessages = [
			WSA_OK					:	"No error",
			WSA_INVALID_HANDLE		:	"Specified event object handle is invalid.",
			WSA_NOT_ENOUGH_MEMORY	: 	"Insufficient memory available.",
			WSA_INVALID_PARAMETER 	:	"One or more parameters are invalid.",
			WSA_OPERATION_ABORTED	:	"Overlapped operation aborted.",
			WSA_IO_INCOMPLETE		:	"Overlapped I/O event object not in signaled state.",
			WSA_IO_PENDING			:	"Overlapped operations will complete later.",
			WSAEINTR				:	"Interrupted function call.",
			WSAEBADF				:	"File handle is not valid.",
			WSAEACCES				:	"Permission denied.",
			WSAEFAULT				:	"Bad address.",
			WSAEINVAL				:	"Invalid argument.",
			WSAEMFILE				:	"Too many open files.",
			WSAEWOULDBLOCK			:	"Resource temporarily unavailable.",
			WSAEINPROGRESS			:	"Operation now in progress.",
			WSAEALREADY				:	"Operation already in progress.",
			WSAENOTSOCK				:	"Socket operation on nonsocket.",
			WSAEDESTADDRREQ			:	"Destination address required.",
			WSAEMSGSIZE				:	"Message too long.",
			WSAEPROTOTYPE			:	"Protocol wrong type for socket.",
			WSAENOPROTOOPT			:	"Bad protocol option.",
			WSAEPROTONOSUPPORT		:	"Protocol not supported.",
			WSAESOCKTNOSUPPORT		:	"Socket type not supported.",
			WSAEOPNOTSUPP			:	"Operation not supported.",
			WSAEPFNOSUPPORT			:	"Protocol family not supported.",
			WSAEAFNOSUPPORT			:	"Address family not supported by protocol family.",
			WSAEADDRINUSE			:	"Address already in use.",
			WSAEADDRNOTAVAIL		:	"Cannot assign requested address.",
			WSAENETDOWN				:	"Network is down.",
			WSAENETUNREACH			:	"Network is unreachable.",
			WSAENETRESET			:	"Network dropped connection on reset.",
			WSAECONNABORTED			:	"Software caused connection abort.",
			WSAECONNRESET			:	"Connection reset by peer.",
			WSAENOBUFS				:	"No buffer space available.",
			WSAEISCONN				:	"Socket is already connected.",
			WSAENOTCONN				:	"Socket is not connected.",
			WSAESHUTDOWN			:	"Cannot send after socket shutdown.",
			WSAETOOMANYREFS			:	"Too many references.",
			WSAETIMEDOUT			:	"Connection timed out.",
			WSAECONNREFUSED			:	"Connection refused.",
			WSAELOOP				:	"Cannot translate name.",
			WSAENAMETOOLONG			:	"Name too long.",
			WSAEHOSTDOWN			:	"Host is down.",
			WSAEHOSTUNREACH			:	"No route to host.",
			WSAENOTEMPTY			:	"Directory not empty.",
			WSAEPROCLIM				:	"Too many processes.",
			WSAEUSERS				:	"User quota exceeded.",
			WSAEDQUOT				:	"Disk quota exceeded.",
			WSAESTALE				:	"Stale file handle reference.",
			WSAEREMOTE				:	"Item is remote.",
			WSASYSNOTREADY			:	"Network subsystem is unavailable.",
			WSAVERNOTSUPPORTED		:	"Winsock.dll version out of range.",
			WSANOTINITIALISED		:	"Successful WSAStartup not yet performed.",
			WSAEDISCON				:	"Graceful shutdown in progress.",
			WSAENOMORE				:	"No more results.",
			WSAECANCELLED			:	"Call has been canceled.",
			WSAEINVALIDPROCTABLE	:	"Procedure call table is invalid.",
			WSAEINVALIDPROVIDER		:	"Service provider is invalid.",
			WSAEPROVIDERFAILEDINIT	:	"Service provider failed to initialize.",
			WSASYSCALLFAILURE		:	"System call failure.",
			WSASERVICE_NOT_FOUND	:	"Service not found.",
			WSATYPE_NOT_FOUND		:	"Class type not found.",
			WSA_E_NO_MORE			:	"No more results.",
			WSA_E_CANCELLED			:	"Call was canceled.",
			WSAEREFUSED				:	"Database query was refused.",
			WSAHOST_NOT_FOUND		:	"Host not found.",
			WSATRY_AGAIN			:	"Nonauthoritative host not found.",
			WSANO_RECOVERY			:	"This is a nonrecoverable error.",
			WSANO_DATA				:	"Valid name, no data record of requested type.",
			WSA_QOS_RECEIVERS		:	"QOS receivers.",
			WSA_QOS_SENDERS			:	"QOS senders.",
			WSA_QOS_NO_SENDERS		:	"No QOS senders.",
			WSA_QOS_NO_RECEIVERS	:	"QOS no receivers.",
			WSA_QOS_REQUEST_CONFIRMED	:	"QOS request confirmed.",
			WSA_QOS_ADMISSION_FAILURE	:	"QOS admission error.",
			WSA_QOS_POLICY_FAILURE		:	"QOS policy failure.",
			WSA_QOS_BAD_STYLE			:	"QOS bad style.",
			WSA_QOS_BAD_OBJECT			:	"QOS bad object.",
			WSA_QOS_TRAFFIC_CTRL_ERROR	:	"QOS traffic control error.",
			WSA_QOS_GENERIC_ERROR		:	"QOS generic error.",
			WSA_QOS_ESERVICETYPE		:	"QOS service type error.",
			WSA_QOS_EFLOWSPEC			:	"QOS flowspec error.",
			WSA_QOS_EPROVSPECBUF		:	"Invalid QOS provider buffer.",
			WSA_QOS_EFILTERSTYLE		:	"Invalid QOS filter style.",
			WSA_QOS_EFILTERTYPE			:	"Invalid QOS filter type.",
			WSA_QOS_EFILTERCOUNT		:	"Incorrect QOS filter count.",
			WSA_QOS_EOBJLENGTH			:	"Invalid QOS object length.",
			WSA_QOS_EFLOWCOUNT			:	"Incorrect QOS flow count.",
			WSA_QOS_EUNKOWNPSOBJ		:	"Unrecognized QOS object.",
			WSA_QOS_EPOLICYOBJ			:	"Invalid QOS policy object.",
			WSA_QOS_EFLOWDESC			:	"Invalid QOS flow descriptor.",
			WSA_QOS_EPSFLOWSPEC			:	"Invalid QOS provider-specific flowspec.",
			WSA_QOS_EPSFILTERSPEC		:	"Invalid QOS provider-specific filterspec.",
			WSA_QOS_ESDMODEOBJ			:	"Invalid QOS shape discard mode object.",
			WSA_QOS_ESHAPERATEOBJ		:	"Invalid QOS shaping rate object.",
			WSA_QOS_RESERVED_PETYPE		:	"Reserved policy QOS element type."
		];
	}

	with (EPosix){
		EPosixMessages = [
			EAI_OVERFLOW	:		"Argument buffer overflow.",
			EAI_SYSTEM		:		"System error returned in `errno'.",
			EAI_MEMORY		:		"Memory allocation failure. ",
			EAI_SERVICE		:		"SERVICE not supported for `ai_socktype'.",
			EAI_SOCKTYPE	:		"`ai_socktype' not supported.",
			EAI_FAMILY		:		"`ai_family' not supported.",
			EAI_FAIL		:		"Non-recoverable failure in name res.",
			EAI_AGAIN		:		"Temporary failure in name resolution.",
			EAI_NONAME		:		"NAME or SERVICE is unknown.",
			EINVALID		:		"Invalid arguments",
			EPERM			:		"Operation not permitted",
			ENOENT			:		"No such file or directory",
			ESRCH			:		"No such process",
			EINTR			:		"Interrupted system call",
			EIO				:		"I/O error",
			ENXIO			:		"No such device or address",
			E2BIG			:		"Argument list too long",
			ENOEXEC			:		"Exec format error",
			EBADF			:		"Bad file number",
			ECHILD			:		"No child processes",
			EAGAIN			:		"Try again",
			ENOMEM			:		"Out of memory",
			EACCES			:		"Permission denied",
			EFAULT			:		"Bad address",
			ENOTBLK			:		"Block device required",
			EBUSY			:		"Device or resource busy",
			EEXIST			:		"File exists",
			EXDEV			:		"Cross-device link",
			ENODEV			:		"No such device",
			ENOTDIR			:		"Not a directory",
			EISDIR			:		"Is a directory",
			EINVAL			:		"Invalid argument",
			ENFILE			:		"File table overflow",
			EMFILE			:		"Too many open files",
			ENOTTY			:		"Not a typewriter",
			ETXTBSY			:		"Text file busy",
			EFBIG			:		"File too large",
			ENOSPC			:		"No space left on device",
			ESPIPE			:		"Illegal seek",
			EROFS			:		"Read-only file system",
			EMLINK			:		"Too many links",
			EPIPE			:		"Broken pipe",
			EDOM			:		"Math argument out of domain of func",
			ERANGE			:		"Math result not representable",
			EDEADLK			:		"Resource deadlock would occur",
			ENAMETOOLONG	:		"File name too long",
			ENOLCK			:		"No record locks available",
			ENOSYS			:		"Function not implemented",
			ENOTEMPTY		:		"Directory not empty",
			ELOOP			:		"Too many symbolic links encountered",
			EWOULDBLOCK		:		"Operation would block",
			ENOMSG			:		"No message of desired type",
			EIDRM			:		"Identifier removed",
			ECHRNG			:		"Channel number out of range",
			EL2NSYNC		:		"Level 2 not synchronized",
			EL3HLT			:		"Level 3 halted",
			EL3RST			:		"Level 3 reset",
			ELNRNG			:		"Link number out of range",
			EUNATCH			:		"Protocol driver not attached",
			ENOCSI			:		"No CSI structure available",
			EL2HLT			:		"Level 2 halted",
			EBADE			:		"Invalid exchange",
			EBADR			:		"Invalid request descriptor",
			EXFULL			:		"Exchange full",
			ENOANO			:		"No anode",
			EBADRQC			:		"Invalid request code",
			EBADSLT			:		"Invalid slot",
			EDEADLOCK		:		"Resource deadlock would occur",
			EBFONT			:		"Bad font file format",
			ENOSTR			:		"Device not a stream",
			ENODATA			:		"No data available",
			ETIME			:		"Timer expired",
			ENOSR			:		"Out of streams resources",
			ENONET			:		"Machine is not on the network",
			ENOPKG			:		"Package not installed",
			EREMOTE			:		"Object is remote",
			ENOLINK			:		"Link has been severed",
			EADV			:		"Advertise error",
			ESRMNT			:		"Srmount error",
			ECOMM			:		"Communication error on send",
			EPROTO			:		"Protocol error",
			EMULTIHOP		:		"Multihop attempted",
			EDOTDOT			:		"RFS specific error",
			EBADMSG			:		"Not a data message",
			EOVERFLOW		:		"Value too large for defined data type",
			ENOTUNIQ		:		"Name not unique on network",
			EBADFD			:		"File descriptor in bad state",
			EREMCHG			:		"Remote address changed",
			ELIBACC			:		"Can not access a needed shared library",
			ELIBBAD			:		"Accessing a corrupted shared library",
			ELIBSCN			:		".lib section in a.out corrupted",
			ELIBMAX			:		"Attempting to link in too many shared libraries",
			ELIBEXEC		:		"Cannot exec a shared library directly",
			EILSEQ			:		"Illegal byte sequence",
			ERESTART		:		"Interrupted system call should be restarted",
			ESTRPIPE		:		"Streams pipe error",
			EUSERS			:		"Too many users",
			ENOTSOCK		:		"Socket operation on non-socket",
			EDESTADDRREQ	:		"Destination address required",
			EMSGSIZE		:		"Message too long",
			EPROTOTYPE		:		"Protocol wrong type for socket",
			ENOPROTOOPT		:		"Protocol not available",
			EPROTONOSUPPORT	:		"Protocol not supported",
			ESOCKTNOSUPPORT	:		"Socket type not supported",
			EOPNOTSUPP		:		"Operation not supported on transport endpoint",
			EPFNOSUPPORT	:		"Protocol family not supported",
			EAFNOSUPPORT	:		"Address family not supported by protocol",
			EADDRINUSE		:		"Address already in use",
			EADDRNOTAVAIL	:		"Cannot assign requested address",
			ENETDOWN		:		"Network is down",
			ENETUNREACH		:		"Network is unreachable",
			ENETRESET		:		"Network dropped connection because of reset",
			ECONNABORTED	:		"Software caused connection abort",
			ECONNRESET		:		"Connection reset by peer",
			ENOBUFS			:		"No buffer space available",
			EISCONN			:		"Transport endpoint is already connected",
			ENOTCONN		:		"Transport endpoint is not connected",
			ESHUTDOWN		:		"Cannot send after transport endpoint shutdown",
			ETOOMANYREFS	:		"Too many references: cannot splice",
			ETIMEDOUT		:		"Connection timed out",
			ECONNREFUSED	:		"Connection refused",
			EHOSTDOWN		:		"Host is down",
			EHOSTUNREACH	:		"No route to host",
			EALREADY		:		"Operation already in progress",
			EINPROGRESS		:		"Operation now in progress",
			ESTALE			:		"Stale file handle",
			EUCLEAN			:		"Structure needs cleaning",
			ENOTNAM			:		"Not a XENIX named type file",
			ENAVAIL			:		"No XENIX semaphores available",
			EISNAM			:		"Is a named type file",
			EREMOTEIO		:		"Remote I/O error",
			EDQUOT			:		"Quota exceeded",
			ENOMEDIUM		:		"No medium found",
			EMEDIUMTYPE		:		"Wrong medium type",
			ECANCELED		:		"Operation Canceled",
			ENOKEY			:		"Required key not available",
			EKEYEXPIRED		:		"Key has expired",
			EKEYREVOKED		:		"Key has been revoked",
			EKEYREJECTED	:		"Key was rejected by service",
			/* for robust mutexes */
			EOWNERDEAD		:		"Owner died",
			ENOTRECOVERABLE	:		"State not recoverable",
			ERFKILL			:		"Operation not possible due to RF-kill",
			EHWPOISON		:		"Memory page has hardware error"
		];
	}
}