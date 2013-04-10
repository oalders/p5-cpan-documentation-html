package App::CpanDocumentationHtml;
# ABSTRACT: Application class

use MooX Options => [ flavour => [qw( pass_through )], protect_argv => 0 ];
use CPAN::Documentation::HTML;
use Cwd;
use Path::Class;

option root => (
	is => 'ro',
	predicate => 1,
	format => 's',
);

option dist => (
	is => 'ro',
	predicate => 1,
	format => 's',
);

option url_prefix => (
	is => 'ro',
	predicate => 1,
	format => 's',
);

option index => (
	is => 'ro',
);

option js => (
	is => 'ro',
	predicate => 1,
	format => 's',
);

option css => (
	is => 'ro',
	predicate => 1,
	format => 's',
);

option bin => (
	is => 'ro',
	format => 's@',
	builder => sub {[]},
);

option lib => (
	is => 'ro',
	format => 's@',
	builder => sub {[]},
);

option default_bins => (
	is => 'ro',
	format => 's@',
	builder => sub {[qw(
		bin
		script
	)]},
);

option default_libs => (
	is => 'ro',
	format => 's@',
	builder => sub {[qw(
		lib
	)]},
);

sub run {
	my ( $self ) = @_;
	my $cd = CPAN::Documentation->new(
		$self->has_root ? ( root => $self->root ) : (),
		$self->has_url_prefix ? ( url_prefix => $self->url_prefix ) : (),
		$self->has_js ? ( js => (scalar file($self->js)->slurp) ) : (),
		$self->has_css ? ( css => (scalar file($self->css)->slurp) ) : (),
	);
	my $dist = $self->has_dist ? $self->dist : "imported_by_".file($0)->basename;
	my $binlib;
	for (@{$self->lib}) {
		$cd->add_lib($dist,$_);
		$binlib = 1;
	}
	for (@{$self->bin}) {
		$cd->add_bin($dist,$_);
		$binlib = 1;
	}
	if (!$binlib || ($binlib && scalar @ARGV)) {
		for my $dir (scalar @ARGV ? @ARGV : $self->has_root ? (getcwd) : (die __PACKAGE__." needs root or a source directory")) {
			for (@{$self->default_libs}) {
				my $lib_dir = dir($dir,$_);
				$cd->add_lib($dist,$lib_dir) if -d $lib_dir;
			}
			for (@{$self->default_bins}) {
				my $bin_dir = dir($dir,$_);
				$cd->add_bin($dist,$bin_dir) if -d $bin_dir;
			}
		}
	}
}

1;

=head1 SUPPORT

IRC

  Join #duckduckgo on irc.freenode.net. Highlight Getty for fast reaction :).

Repository

  http://github.com/Getty/p5-cpan-documentation
  Pull request and additional contributors are welcome
 
Issue Tracker

  http://github.com/Getty/p5-cpan-documentation/issues
