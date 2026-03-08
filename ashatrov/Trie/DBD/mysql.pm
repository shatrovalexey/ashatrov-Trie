package ashatrov::Trie::DBD::mysql;
use strict;

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

	$self->{'dba'}->do($_) foreach <<".", <<".";
DROP TEMPORARY TABLE IF EXISTS `$table->{'result'}`;
.
CREATE TEMPORARY TABLE IF NOT EXISTS `$table->{'result'}`(
	`id_node` BIGINT UNSIGNED NOT null
	, `table_node` VARCHAR(20) CHARSET latin1 NOT null
	, `weight` INT UNSIGNED NOT null

	, UNIQUE(`table_node`, `id_node`)
	, INDEX(`weight`)
);
.
	my $sth_ins = $self->{'dba'}->prepare(<<".");
INSERT IGNORE INTO
	`$table->{'result'}`(`id_node`, `table_node`, `weight`)
WITH RECURSIVE `$table->{'temp'}` AS (
	SELECT 
		`id`,
		`id_parent`,
		`id_node`,
		`table_node`,
		1 as `pos`
	FROM
		`$self->{'table'}` AS `t1` FORCE INDEX (`idx_fts_search`)
	WHERE
		(`char` = ?)

	UNION ALL

	SELECT
		`c`.`id`,
		`c`.`id_parent`,
		`c`.`id_node`,
		`c`.`table_node`,
		`wc`.`pos` + 1
	FROM
		`$table->{'temp'}` AS `wc`

			INNER JOIN `$self->{'table'}` AS `c` FORCE INDEX (`idx_fts_parent`)
				ON (`c`.`id_parent` = `wc`.`id`)
					AND (`c`.`char` = substring(?, `wc`.`pos` + 1, 1))
)
SELECT
	`t1`.`id_node`
	, `t1`.`table_node`
	, count(*) AS `weight`
FROM
	`$table->{'temp'}` AS `t1`
WHERE
	(`t1`.`pos` = ?)
GROUP BY
	1, 2;
.
	$sth_ins->execute(substr($_, 0, 1), $_, length) foreach @$words;
	$sth_ins->finish;

	my @args;
	my $sql = <<".";
SELECT
	`t1`.`table_node` AS `table`
	, `t1`.`id_node` AS `id`
	, `t1`.`weight`
FROM
	`$table->{'result'}` AS `t1`
.
	$sql .= <<"." if $mode;
WHERE
	(`t1`.`weight` $mode ?)
.
	$sql .= <<'.';
ORDER BY
	3 DESC;
.
	push @args, scalar @$words if $mode;

	my $result = $self->{'dba'}->selectall_arrayref($sql, {'Slice' => {},}, @args);

	$self->{'dba'}->do(<<".");
DROP TEMPORARY TABLE IF EXISTS `$table->{'result'}`;
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

	, INDEX `id_parent` (`id_parent`, `char`)
	, INDEX `char` (`char`)
	, PRIMARY KEY(`id`)
	, INDEX `id_node` (`id_node`, `table_node`)
	, INDEX `idx_fts_search` (`char`, `id_parent`, `id`, `id_node`, `table_node`)
	, INDEX `idx_fts_parent` (`id_parent`, `char`, `id`)
	, INDEX `idx_fts_node` (`id_node`, `table_node`)
	, FOREIGN KEY(`id_parent`)
		REFERENCES `$self->{'table'}` (`id`)
		ON DELETE CASCADE
		ON UPDATE CASCADE
);
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
) ENGINE = CSV;
.
	my $sth_sel = $self->{'dba'}->prepare($sqlSelect);
	$sth_sel->execute(@sqlSelectArgs);

	my ($sqlPrefix, $sqlSuffix) = (<<".", <<'.');
INSERT IGNORE INTO
	`$temp`(`id_parent`, `id`, `id_node`, `char`)
VALUES
.
(?, ?, ?, ?)
.
	my $maxSTH = 20;
	my $getSTH = sub {
		my $count = shift;

		return unless $count;

		$self->{'dba'}->prepare_cached($sqlPrefix . join(', ', ($sqlSuffix) x $count) . ';')
	};
	my $sth_ins = $getSTH->($maxSTH);

	my ($count, @data) = 0;

	while (my ($id_node, $fts) = $sth_sel->fetchrow_array) {
		&utf8::decode($fts);

		warn $id_node;

		while ($fts =~ m{\w+}gcsu) {
			my $word = $&;

			while ($word =~ m{.}gcsu) {
				push @data, $id_char ++, $id_char, $id_node, $&;

				next if ++ $count < $maxSTH;

				$sth_ins->execute(@data);

				($count, @data) = 0
			}
		}
	}

	$getSTH->($count)->execute(@data) if @data;

	$sth_ins->finish;
	$sth_sel->finish;

	my $result = int $self->{'dba'}->do(<<".", undef, $table);
INSERT IGNORE INTO
	`$self->{'table'}`(`id_parent`, `id`, `id_node`, `char`, `table_node`)
SELECT
	if(`t1`.`id_parent`, `t1`.`id_parent`, null) AS `id_parent`
	, `t1`.`id`
	, `t1`.`id_node`
	, `t1`.`char`
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