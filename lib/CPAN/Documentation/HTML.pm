package CPAN::Documentation::HTML;
# ABSTRACT: Generate files for documentations of CPAN Distributions or simple packages

use Moo;
use Cwd;
use Path::Class;
use JSON;
use File::Copy;
use Pod::Simple::HTML;

has root => (
	is => 'ro',
	lazy => 1,
	builder => sub { dir(getcwd)->absolute->stringify },
);

has pod => (
	is => 'ro',
	lazy => 1,
	builder => sub { dir(shift->root,'pod')->absolute->stringify },
);

has html => (
	is => 'ro',
	lazy => 1,
	builder => sub { dir(shift->root,'perldoc')->absolute->stringify },
);

has url_prefix => (
	is => 'ro',
	lazy => 1,
	builder => sub { '/perldoc/' },
);

has cache_file => (
	is => 'ro',
	lazy => 1,
	builder => sub { file(shift->root,'.cpandoc.cache')->absolute->stringify },
);

has _pod_simple_html => (
	is => 'ro',
	lazy => 1,
	builder => sub { Pod::Simple::HTML->new },
);

has cache => (
	is => 'ro',
	lazy => 1,
	builder => sub {
		my ( $self ) = @_;
		return decode_json(file($self->cache_file)->slurp) if -f $self->cache_file;
		return {};
	},
);

sub save_cache {
	my ( $self ) = @_;
	file($self->cache_file)->spew(encode_json($self->cache));
}

sub BUILD {
	my ( $self ) = @_;
	die __PACKAGE__." Directory ".$self->root." does not exist" unless -d $self->root;
}

sub add_lib {
	my ( $self, $dist, $path ) = @_;
	my ( @pods, @pms );
	my $dir = dir($path);
	$dir->traverse(sub {
		my $b = $_[0]->basename;
		if ($b =~ qr!\.pm$!) {
			push @pms, $_[0];
		} elsif ($b =~ qr!\.pod$!) {
			push @pods, $_[0];
		}
		return $_[1]->();
	});
	my %modules;
	for my $file (@pods) {
		my @parts = $file->relative(dir($path))->components;
		my $filename = pop @parts;
		my $module_last = $filename =~ s!\.pod$!!;
		my $module = join('::',@parts,$module_last);
		$modules{$module} = $file;
	}
	for my $file (@pms) {
		my @parts = $file->relative(dir($path))->components;
		my $filename = pop @parts;
		$filename =~ s!\.pm$!!;
		my $module = join('::',@parts,$filename);
		$modules{$module} = $file unless defined $modules{$module};
	}
	for (sort keys %modules) {
		$self->_add_module($dist,$_,$dir,$modules{$_});
	}
	$self->save_cache;
}

sub add_bin {
	my ( $self, $dist, $path ) = @_;
	my $dir = dir($path);
	while (my $file = $dir->next) {
		next unless -f $file;
		my $module = $file->basename;
		$self->_add_module($dist,$module,$dir,$file,'is_script');
	}
	$self->save_cache;
}

sub pod_file { file(shift->pod,(shift).'.pod') }

sub _add_module {
	my ( $self, $dist, $module, $dir, $file, $is_script ) = @_;
	my $filename = file($file)->relative($dir);
	my $target = $self->pod_file($module);
	$target->dir->mkpath;
	copy($file->stringify,$target->stringify) or die __PACKAGE__." copy failed: $!";
	$self->cache->{$module} = $dist;
	$self->_add_module_html($module,$target);
}

sub _add_module_html {
	my ( $self, $module, $file ) = @_;
	my $psh = Pod::Simple::HTML->new;
	my $html;
	$psh->output_string($html);
	$psh->parse_file($file->stringify);
	my $target = file($self->html,$module,'index.html');
	$target->dir->mkpath;
	$target->spew($html);
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
