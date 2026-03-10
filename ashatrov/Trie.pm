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
	, 'RX_WORD' => qr{\w+}us
	, 'RX_LETTER' => qr{.}us
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

	$args->{'word'} ||= &RX_WORD();
	$args->{'letter'} ||= &RX_LETTER();
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
sub _getLetter($\&;@) {
	my ($self, $sub) = splice @_, 0, 2;
	my ($i, @result) = 0;

	foreach my $str (@_) {
		my $j = 0;
		&utf8::decode($str);

		while ($str =~ m{$self->{'word'}}gc) {
			my ($word, $k) = ($&, 0);

			while ($word =~ m{$self->{'letter'}}gc) {
				my $letter = $&;

				$sub->($k => \$letter, $j => \$word, $i => \$str)
			} continue {
				$k ++
			}
		} continue {
			$j ++
		}
	} continue {
		$i ++
	}

	@result
}
sub clean($;@) {
	my $self = shift;
	my $sub = $self->_getSubName('clean');

	$self->$sub(@_)
}
sub search($$;$) {
	my $self = shift;
	my @words = uniqstr uc(shift) =~ m{$self->{'word'}}go or return;
	my $mode = shift || &FTS_MODE_EQ();
	my $sub = $self->_getSubName('search');
	my %table = map {+ $_ => $self->_getTableName($_),} qw{search result words};

	$self->$sub(\@words, \%table, $mode)
}
sub build($$$;@) {
	my $self = shift;
	my $temp = $self->_getTableName('build');
	my $sub = $self->_getSubName('build');

	$self->$sub($temp, @_)
}

+ 1