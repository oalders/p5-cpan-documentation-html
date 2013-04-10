#!/usr/bin/env perl
use strict;
use warnings;
use Test::LoadAllModules;

BEGIN {
	all_uses_ok( search_path => 'CPAN::Documentation::HTML' );
	all_uses_ok( search_path => 'App::CpanDocumentationHtml' );
}
