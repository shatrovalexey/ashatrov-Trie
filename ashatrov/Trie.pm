package ashatrov::Trie;
use parent qw{Object::Tiny};
use strict;
use utf8;
use Module::Load qw{load};
use List::Util qw{uniqstr};
use constant {
	'POSTFIX' => 'fts'
	, 'DELIMITER' => '::'
	, 'SEPARATOR' => '_'
	, 'FTS_MODE_EQ' => '='
	, 'FTS_MODE_GT' => '>'
	, 'FTS_MODE_LT' => '<'
	, 'FTS_MODE_GTE' => '>='
	, 'FTS_MODE_LTE' => '<='
	, 'FTS_MODE_FREE' => ''
	,
};

sub new($;%) {
	my ($package, %args) = @_;

	warn 'Prepare failed' and return unless $package->_prepare(\%args);

	+ $package->SUPER::new(%args)
}
sub _prepare($\%) {
	my ($package, $args) = @_;

	warn 'No dba' and return unless exists $args->{'dba'}{'Driver'}{'Name'};

	$args->{'driver'} = $package->_getName(__PACKAGE__, 'DBD', lc $args->{'dba'}{'Driver'}{'Name'});

	eval {load $args->{'driver'}};
	warn $@ and return if $@;

	$args->{'table'} = &_getTableName($args, &POSTFIX());

	+ 1

}
sub _getTableName($@) {
	my $self = shift;

	+ join &SEPARATOR(), grep length, map split(m{\W+}uso, $_), $self->{'table'}, @_
}
sub _getName($@) {shift; join &DELIMITER(), @_}
sub _getSubName($$) {
	my ($self, $subName) = @_;

	$self->_getName($self->{'driver'}, $subName)
}
sub clean($;@) {
	my $self = shift;
	my $sub = $self->_getSubName('clean');

	$self->$sub(@_)
}
sub search($$;$) {
	my $self = shift;
	my @words = uniqstr uc(shift) =~ m{\w+}guso or return;
	my $mode = shift || &FTS_MODE_EQ();
	my $sub = $self->_getSubName('search');
	my %table = (
		'temp' => $self->_getTableName('search')
		, 'result' => $self->_getTableName('result')
		,
	);

	$self->$sub(\@words, \%table, $mode)
}
sub build($$$;@) {
	my $self = shift;
	my $temp = $self->_getTableName('build');
	my $sub = $self->_getSubName('build');

	$self->$sub($temp, @_)
}

+ 1