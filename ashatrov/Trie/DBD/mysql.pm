package ashatrov::Trie::DBD::mysql;
use strict;
use constant {
	'MAX_ROWS' => 40
	,
};

sub clean($;@) {
	my ($self, @nodes) = @_;
	my ($result, $sqlWhere) = (0, q{});

	$sqlWhere .= <<"." if @nodes;
WHERE
	(`t1`.`table_node` IN (${\join q{,}, ('?') x @nodes}))
.
	my $sth_del = $self->{'dba'}->prepare(<<".");
DELETE
	`t1`.*
FROM
	`$self->{'table'}` AS `t1`
$sqlWhere;
.
	$result += $sth_del->execute($_) foreach @_;
	$sth_del->finish;

	$result
}
sub search($\@\%;$) {
	my ($self, $words, $table, $mode) = @_;

	$self->{'dba'}->do(<<".") foreach @$table{+ qw{words result}};
DROP TEMPORARY TABLE IF EXISTS `$_`;
.
	$self->{'dba'}->do(<<".");
CREATE TEMPORARY TABLE IF NOT EXISTS `$table->{'result'}`(
	`id_node` BIGINT UNSIGNED NOT null
	, `table_node` VARCHAR(20) CHARSET latin1 NOT null
	, `weight` TINYINT UNSIGNED NOT null

	, PRIMARY KEY(`table_node`, `id_node`)
	, INDEX(`weight`)
);
.
	$self->{'dba'}->do(<<"." . join(<<'.', (<<'.') x @$words), undef, @$words);
CREATE TEMPORARY TABLE IF NOT EXISTS `$table->{'words'}`(
	`word` VARCHAR(50) NOT null
	, `char` CHAR(1) GENERATED ALWAYS AS (substring(`word` FROM 1 FOR 1)) STORED
	, `length` TINYINT UNSIGNED GENERATED ALWAYS AS (char_length(`word`)) STORED

	, PRIMARY KEY(`word`)
) IGNORE AS
.
UNION DISTINCT
.
SELECT
	? AS `word`;
.
	my $sqlSel = <<".";
SELECT
	`t1`.`id_node`
	, `t1`.`table_node`
	, count(*) as `weight`
FROM
	`$table->{'words'}` AS `w`

		CROSS JOIN LATERAL (
			WITH RECURSIVE `$table->{'search'}` AS (
				SELECT 
					`t1`.id,
					`t1`.id_parent,
					`t1`.id_node,
					`t1`.table_node,
					1 as pos
				FROM
					`$self->{'table'}` AS `t1` FORCE INDEX(`idx_fts_search`)
				WHERE
					(`t1`.`char` = `w`.`char`)
						AND (`w`.`length` > 0)
				UNION ALL
				SELECT
					`c`.`id`
					, `c`.`id_parent`
					, `c`.`id_node`
					, `c`.`table_node`
					, `wc`.`pos` + 1 AS `pos`
				FROM
					`$table->{'search'}` AS `wc`

						INNER JOIN `$self->{'table'}` AS `c` FORCE INDEX(`id_parent_char`)
							ON (`c`.`id_parent` = `wc`.`id`)
								AND (`c`.`char` = substring(`w`.`word`, `wc`.`pos` + 1, 1))
				WHERE
					(`wc`.`pos` < `w`.`length`)
			)
			SELECT
				`fs1`.`id_node`
				, `fs1`.`table_node`
			FROM
				`$table->{'search'}` AS `fs1`
			WHERE
				(`fs1`.`pos` = `w`.`length`)
		) AS `t1`
GROUP BY
	`w`.`word`
	, `t1`.`id_node`
	, `t1`.`table_node`;
.
	# die $sqlSel, "\n", @{$self->{'dba'}->selectcol_arrayref(qq{EXPLAIN ANALYZE $sqlSel})};

	$self->{'dba'}->do(<<".");
INSERT IGNORE INTO
	`$table->{'result'}`(`id_node`, `table_node`, `weight`)
$sqlSel
.
	my $sql = <<"."; $sql .= <<"." if $mode; $sql .= <<'.';
SELECT
	`t1`.`table_node` AS `table`
	, `t1`.`id_node` AS `id`
	, `t1`.`weight`
FROM
	`$table->{'result'}` AS `t1`
.
WHERE
	(`t1`.`weight` $mode ?)
.
ORDER BY
	`t1`.`weight` DESC;
.
	my @args;

	push @args, scalar @$words if $mode;

	my $result = $self->{'dba'}->selectall_arrayref($sql, {'Slice' => {},}, @args);

	$self->{'dba'}->do(<<".") foreach @$table{+ qw{words result}};
DROP TEMPORARY TABLE IF EXISTS `$_`;
.
	$result
}
sub build($$$$;@) {
	my ($self, $temp, $table, $sqlSelect, @sqlSelectArgs) = @_;

	$self->{'dba'}->do(<<".");
CREATE TABLE IF NOT EXISTS `$self->{'table'}`(
	`id` BIGINT UNSIGNED NOT null
	, `id_parent` BIGINT UNSIGNED null
	, `id_node` BIGINT UNSIGNED NOT null
	, `table_node` VARCHAR(20) CHARSET latin1 NOT null
	, `char` CHAR(1) CHARACTER SET utf8mb4 NOT null
	, `is_root` TINYINT UNSIGNED GENERATED ALWAYS AS (`id_parent` IS null) STORED
	, `length` TINYINT UNSIGNED NOT null

	, INDEX(`id`)
	, INDEX `id_parent_char`(`id_parent`, `char`)
	, INDEX `id_node_table_node`(`id_node`,`table_node`)
	, INDEX `idx_fts_search`(`char`, `id_parent`, `id`, `id_node`, `table_node`)
) PARTITION BY KEY(`char`) PARTITIONS 64;
.
	my ($id_char) = @{$self->{'dba'}->selectcol_arrayref(<<".", undef, 1)} or return;
SELECT
	max(`t1`.`id`) + ? AS `id`
FROM
	`$self->{'table'}` AS `t1`;
.
	$self->{'dba'}->do($_) foreach <<".", <<".";
DROP TEMPORARY TABLE IF EXISTS `$temp`;
.
CREATE TEMPORARY TABLE IF NOT EXISTS `$temp`(
	`id` BIGINT UNSIGNED NOT null
	, `id_parent` BIGINT UNSIGNED NOT null
	, `id_node` BIGINT UNSIGNED NOT null
	, `char` CHAR(1) NOT null
	, `length` TINYINT UNSIGNED NOT null
) ENGINE = CSV;
.
	my $sth_sel = $self->{'dba'}->prepare($sqlSelect);
	$sth_sel->execute(@sqlSelectArgs);

	my ($sqlPrefix, $sqlSuffix) = (<<".", <<'.');
INSERT IGNORE INTO
	`$temp`(`id_parent`, `id`, `id_node`, `char`, `length`)
VALUES
.
(?, ?, ?, ?, ?)
.
	my $maxSTH = &MAX_ROWS();
	my $getSTH = sub {
		my $count = shift;

		return unless $count;

		$self->{'dba'}->prepare_cached($sqlPrefix . join(', ', ($sqlSuffix) x $count) . ';')
	};
	my $sth_ins = $getSTH->($maxSTH);

	my ($count, @data) = 0;

	while (my ($id_node, $fts) = $sth_sel->fetchrow_array) {
		warn $id_node;

		$self->_getLetter(sub($$$$$$) {
			my ($k, $letter, $j, $word) = @_;
			my $id_parent = $k ? qq{$id_char} : 0;
			my $length = length qq{$$word};

			push @data, $id_parent, ++ $id_char, qq{$id_node}, qq{$$letter}, $length;

			return if ++ $count < $maxSTH;

			$sth_ins->execute(@data);

			($count, @data) = 0
		}, $fts)
	}

	$sth_ins->finish;

	if (@data) {
		$sth_ins = $getSTH->($count);
		$sth_ins->execute(@data);
		$sth_ins->finish;
	}

	$_->finish foreach $sth_ins, $sth_sel;

	my $result = int $self->{'dba'}->do(<<".", undef, 0, undef, $table);
INSERT IGNORE INTO
	`$self->{'table'}`(`id_parent`, `id`, `id_node`, `char`, `length`, `table_node`)
SELECT
	if(`t1`.`id_parent` > ?, `t1`.`id_parent`, ?) AS `id_parent`
	, `t1`.`id`
	, `t1`.`id_node`
	, `t1`.`char`
	, `t1`.`length`
	, ? AS `table_node`
FROM
	`$temp` AS `t1`;
.
	$self->{'dba'}->do(<<".");
DROP TEMPORARY TABLE IF EXISTS `$temp`;
.
	$result
}

+ 1