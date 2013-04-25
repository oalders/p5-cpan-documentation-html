package CPAN::Documentation::HTML::Entry;
# ABSTRACT: An entry (a module, binary or documentation) in the HTML

use Moo;

has module => (
	is => 'ro',
	required => 1,
);

has dist => (
	is => 'ro',
	required => 1,
);

# 
# 0 Module
# 1 Documentation
# 2 Script
#

has type => (
	is => 'ro',
	required => 1,
);

has pod => (
	is => 'ro',
	required => 1,
);

1;