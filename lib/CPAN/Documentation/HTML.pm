package CPAN::Documentation::HTML;
# ABSTRACT: Generate files for documentations of CPAN Distributions or simple packages

use Moo;
use Cwd;
use Path::Class;
use JSON;
use File::Copy;
use CPAN::Documentation::HTML::PodSimple;
use CPAN::Documentation::HTML::Entry;
use Dist::Data;
use File::Temp qw( tempdir );
use HTML::Zoom;
use HTML::TreeBuilder;

has root => (
	is => 'ro',
	lazy => 1,
	builder => sub { dir(getcwd)->absolute->stringify },
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

has index_name => (
	is => 'ro',
	lazy => 1,
	builder => sub { 'Modules Index' },
);

has template => (
	is => 'ro',
	lazy => 1,
	builder => sub { <<__EOTEMPLATE__; },
<div class="cdh-module">Sample::Module</div>
<div class="cdh-body">
<div id="cdh-index">
  <div class="cdh-index-list">
    <div class="cdh-index-dist">
      <div class="cdh-index-dist-name">MyDist-0.001.tar.gz</div>
      <div class="cdh-index-dist-documentation">
        <div class="cdh-index-dist-name"><a>MyManual</a></div>
      </div>
      <div class="cdh-index-dist-modules">
        <div class="cdh-index-dist-name"><a>MyModule</a></div>
      </div>
      <div class="cdh-index-dist-scripts">
        <div class="cdh-index-dist-name"><a>a_script.pl</a></div>
      </div>
    </div>
  </div>
</div> 
</div>
__EOTEMPLATE__
);

has cache_file => (
	is => 'ro',
	lazy => 1,
	builder => sub { file(shift->root,'.cpandochtml.cache')->absolute->stringify },
);

has _pod_simple_html => (
	is => 'ro',
	lazy => 1,
	builder => sub { Pod::Simple::HTML->new },
);

has _json => (
	is => 'ro',
	lazy => 1,
	builder => sub {
		my $json = JSON->new;
		return $json;
	}
);

has cache => (
	is => 'ro',
	lazy => 1,
	builder => sub {
		my ( $self ) = @_;
		if (-f $self->cache_file) {
			my %cache = %{$self->_json->decode(file($self->cache_file)->slurp)};
			for (keys %cache) {
				$cache{$_} = CPAN::Documentation::HTML::Entry->new(
					pod => $cache{$_}->{pod},
					module => $cache{$_}->{module},
					type => $cache{$_}->{type},
					dist => $cache{$_}->{dist},
				);
			}
			return \%cache;
		} else {
			{}
		}
	},
);

sub save_cache {
	my ( $self ) = @_;
	my %cache = %{$self->cache};
	for (keys %cache) {
		$cache{$_} = {
			pod => $cache{$_}->pod,
			module => $cache{$_}->module,
			type => $cache{$_}->type,
			dist => $cache{$_}->dist,
		};
	}
	file($self->cache_file)->spew($self->_json->encode(\%cache));
}

sub save_index {
	my ( $self ) = @_;
	my $target = file($self->html,'index.html');
	my $zoom = HTML::Zoom->from_html($self->template);

	my %dists;

	for (keys %{$self->cache}) {
		my $entry = $self->cache->{$_};
		$dists{$entry->dist} = {} unless defined $dists{$entry->dist};
		for ([0,'modules'],[1,'documentation'],[2,'scripts']) {
			if ($entry->type == $_->[0]) {
				$dists{$entry->dist}->{$_->[1]} = [] unless defined $dists{$entry->dist}->{$_->[1]};
				push @{$dists{$entry->dist}->{$_->[1]}}, $entry;
			}
		}
	}

	use DDP; p(%dists);

	$target->spew($zoom->to_html);
}

sub BUILD {
	my ( $self ) = @_;
	die __PACKAGE__." Directory ".$self->root." does not exist" unless -d $self->root;
}

sub add_dist {
	my ( $self, $distfile ) = @_;
	my $distname = file($distfile)->basename;
	my $distdir = tempdir;
	my $dist = Dist::Data->new( filename => $distfile, dir => $distdir )->extract_distribution;
	if (-d dir($distdir,'lib')) {
		$self->add_lib($distname, dir($distdir,'lib'));
	}
	if (-d dir($distdir,'bin')) {
		$self->add_bin($distname, dir($distdir,'bin'));
	}
	if (-d dir($distdir,'script')) {
		$self->add_bin($distname, dir($distdir,'script'));
	}
}

sub get_entry {
	my ( $self, $module, $file, $type, $dist ) = @_;
	my @lines = file($file)->slurp;
	my $pod;
	for (@lines) {
		if (/^=\w+/../^=(cut)\s*$/) {
			$pod .= $_ . ( $1 ?"\n":"" )
		}
	}
	return CPAN::Documentation::HTML::Entry->new(
		pod => $pod,
		module => $module,
		type => 1,
		dist => $dist,
	);
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
		$filename =~ s!\.pod$!!;
		my $module = join('::',@parts,$filename);
		$modules{$module} = $self->get_entry( $module, $file, 1, $dist );
	}
	for my $file (@pms) {
		my @parts = $file->relative(dir($path))->components;
		my $filename = pop @parts;
		$filename =~ s!\.pm$!!;
		my $module = join('::',@parts,$filename);
		$modules{$module} = $self->get_entry( $module, $file, 0, $dist )
			unless defined $modules{$module};
	}
	for (sort keys %modules) {
		$self->add_entry($modules{$_});
	}
}

sub add_bin {
	my ( $self, $dist, $path ) = @_;
	my $dir = dir($path);
	while (my $file = $dir->next) {
		next unless -f $file;
		my $module = $file->basename;
		$self->add_entry($self->get_entry( $module, $file, 2, $dist ));
	}
}

sub add_entry {
	my ( $self, $entry ) = @_;
	my $html_target = file($self->html,$entry->module,'index.html');
	$html_target->dir->mkpath;
	my $psh = CPAN::Documentation::HTML::PodSimple->new;
	$psh->perldoc_url_prefix($self->url_prefix);
	my $pod_simple_html = '';
	$psh->output_string(\$pod_simple_html);
	$psh->index(1);
	$psh->parse_string_document($entry->pod);
	my $tree = HTML::TreeBuilder->new_from_content($pod_simple_html);
	my $body = $tree->find_by_tag_name('body');
	my $body_html = join('',map { $_->as_XML } $body->content_list);
	my $zoom = HTML::Zoom->from_html($self->template)
		->select('.cdh-module')->replace_content($entry->module)
		->select('.cdh-body')->replace_content(\$body_html);
	$html_target->spew($zoom->to_html);
	$self->cache->{$entry->module} = $entry;
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
