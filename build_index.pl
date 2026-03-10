#!/usr/bin/perl -I. -Ilib

use strict;
use ashatrov::Trie;
require 'elapsed.pm';

# ПОСТРОИТЬ ИНДЕКС
my $dba = require('dba.pm');
# описан драйвер только для MySQL v8x
my $idxh = ashatrov::Trie->new(
	'dba' => $dba
	, 'table' => 'offer'
	, 'word' => qr{[a-zA-Z0-9-]+}us
);

warn 'rows: ', $idxh->build('offer' => <<'.', ' ');
SELECT
	`o1`.`id`
	, upper(trim(concat_ws(?, `o1`.`art`, `o1`.`name`, `o1`.`title`))) AS `fts`
FROM
	`parser6`.`offer` AS `o1`;
.

+ 1