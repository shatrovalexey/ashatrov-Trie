use strict;
use DBI;

+ DBI->connect('dbi:mysql:test', 'root', 'f2ox9erm', {
	'RaiseError' => 1
	, 'mysql_auto_reconnect' => 1
	, 'mysql_use_result ' => 1
	, 'mysql_enable_utf8mb4' => 1
	, 'mysql_server_prepare' => 1
	, 'mysql_utf8_semantics' => 1
})