#!/usr/bin/perl -I.

use strict;
use ashatrov::Trie;

# ПОСТРОИТЬ ИНДЕКС
# описан драйвер только для MySQL v8x
my $idxh = ashatrov::Trie->new('dba' => require('dba.pm'), 'table' => 'offer');
warn $idxh->build('offer' => <<'.', ' ');
SELECT
	`o1`.`id`
	, upper(trim(concat_ws(?, `o1`.`art`, `o1`.`name`, `o1`.`title`))) AS `fts`
FROM
	`offer` AS `o1`;
.

+ 1