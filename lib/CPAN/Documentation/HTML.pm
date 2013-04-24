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
use File::ShareDir::ProjectDistDir;

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

has assets => (
	is => 'ro',
	lazy => 1,
	builder => sub {{
		"default.css" => file(dist_dir('CPAN-Documentation-HTML'),'default.css'),
		"default.png" => file(dist_dir('CPAN-Documentation-HTML'),'default.png'),
	}},
);

has template => (
	is => 'ro',
	lazy => 1,
	builder => sub { file(dist_dir('CPAN-Documentation-HTML'),'default.html')->slurp },
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

sub replace_assets {
	my ( $self, $zoom ) = @_;
	for (keys %{$self->assets}) {
		my $file = $_;
		my $id_file = $file;
		$id_file =~ s/\./-/g;
		for (qw( src href )) {
			$zoom = $zoom->select('#cdh-'.$_.'-'.$id_file)->add_to_attribute( $_ => $self->url_prefix.$file );
		}
	}
	return $zoom;
}

sub save_index {
	my ( $self ) = @_;
	my $target = file($self->html,'index.html');
	my $zoom = HTML::Zoom->from_html($self->template);

	$zoom = $self->replace_assets($zoom);

	for (keys %{$self->assets}) {
		copy($self->assets->{$_},file($self->html,$_));
	}

	my @tm = ([1,'documentation'],[2,'scripts'],[0,'modules']);

	my %dists;

	for (keys %{$self->cache}) {
		my $entry = $self->cache->{$_};
		$dists{$entry->dist} = {} unless defined $dists{$entry->dist};
		for (@tm) {
			if ($entry->type == $_->[0]) {
				$dists{$entry->dist}->{$_->[1]} = [] unless defined $dists{$entry->dist}->{$_->[1]};
				push @{$dists{$entry->dist}->{$_->[1]}}, $entry;
			}
		}
	}

	$target->spew($zoom->select('.cdh-index-list')->repeat_content([ map {
		my $dist = $_;
		sub {
			my $distzoom = $_;
			my $entry_matrix = $dists{$dist};
			$distzoom = $distzoom->select('.cdh-index-dist-name')->replace_content($dist);
			for (@tm) {
				my $typename = $_->[1];
				if (defined $entry_matrix->{$typename}) {
					my @entries = @{$entry_matrix->{$typename}};
					$distzoom = $distzoom
					->select('.cdh-index-dist-'.$typename.'-list')
					->repeat_content([ map {
						my $entry = $_;
						return unless $entry->pod;
						sub {
							$_->select('.cdh-index-entry')
								->add_to_attribute( href => $self->url_prefix.$entry->module )
								->then
								->replace_content($entry->module)
						}
					} @entries ]);
				} else {
					$distzoom = $distzoom->select('.cdh-index-dist-'.$typename)->replace('');
				}
			}
			return $distzoom;
		};
	} sort { $a cmp $b } keys %dists ])->to_html);
}

sub BUILD {
	my ( $self ) = @_;
	die __PACKAGE__." Directory ".$self->root." does not exist" unless -d $self->root;
}

sub add_dist {
	my ( $self, $distfile ) = @_;
	my $distdir = tempdir;
	my $distdata = Dist::Data->new( filename => $distfile, dir => $distdir );
	$distdata->extract_distribution;
	my $dist = $distdata->name;
	if (-d dir($distdir,'lib')) {
		$self->add_lib($dist, dir($distdir,'lib'));
	}
	if (-d dir($distdir,'bin')) {
		$self->add_bin($dist, dir($distdir,'bin'));
	}
	if (-d dir($distdir,'script')) {
		$self->add_bin($dist, dir($distdir,'script'));
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
		type => $type,
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
		->select('.cdh-title')->replace_content($entry->dist.' - '.$entry->module)
		->select('.cdh-body')->replace_content(\$body_html);
	$zoom = $self->replace_assets($zoom);
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
