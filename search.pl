#!/usr/bin/perl -I. -Ilib

use strict;
use ashatrov::Trie;
require 'elapsed.pm';

# ПОИСК

my $query = 'tn';
my $dba = require('dba.pm');
# описан драйвер только для MySQL v8x
my $idxh = ashatrov::Trie->new('dba' => $dba, 'table' => 'offer');
my $data = $idxh->search($query, &ashatrov::Trie::FTS_MODE_GTE());

warn 'rows: ', scalar @$data;