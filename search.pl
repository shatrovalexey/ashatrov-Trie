#!/usr/bin/perl -I.

use strict;
use ashatrov::Trie;
use Data::Dumper;

# ПОИСК

my $query = 'tn';

# описан драйвер только для MySQL v8x
my $idxh = ashatrov::Trie->new('dba' => require('dba.pm'), 'table' => 'offer');
my $data = $idxh->search($query, &ashatrov::Trie::FTS_MODE_GTE());

warn scalar @$data;