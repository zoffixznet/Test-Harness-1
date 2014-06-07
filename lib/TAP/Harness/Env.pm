package TAP::Harness::Env;

use strict;
use warnings;

use constant IS_VMS => ( $^O eq 'VMS' );
use TAP::Object;
use Text::ParseWords qw/shellwords/;

our $VERSION = '3.31';

# Get the parts of @INC which are changed from the stock list AND
# preserve reordering of stock directories.
sub _filtered_inc_vms {
    my @inc = grep { !ref } @INC;    #28567

    # VMS has a 255-byte limit on the length of %ENV entries, so
    # toss the ones that involve perl_root, the install location
    @inc = grep { !/perl_root/i } @inc;

    my @default_inc = _default_inc();

    my @new_inc;
    my %seen;
    for my $dir (@inc) {
        next if $seen{$dir}++;

        if ( $dir eq ( $default_inc[0] || '' ) ) {
            shift @default_inc;
        }
        else {
            push @new_inc, $dir;
        }

        shift @default_inc while @default_inc and $seen{ $default_inc[0] };
    }
    return @new_inc;
}

# Cache this to avoid repeatedly shelling out to Perl.
my @inc;

sub _default_inc {
    return @inc if @inc;

    local $ENV{PERL5LIB};
    local $ENV{PERLLIB};

    my $perl = $ENV{HARNESS_PERL} || $^X;

    # Avoid using -l for the benefit of Perl 6
    chomp( @inc = `"$perl" -e "print join qq[\\n], \@INC, q[]"` );
    return @inc;
}

sub create {
	my $package = shift;
    my %input = %{ shift || {} };

    my @libs         = @{ delete $input{libs}     || [] };
    my @raw_switches = @{ delete $input{switches} || [] };
    my @opt
      = ( @raw_switches, shellwords( $ENV{HARNESS_PERL_SWITCHES} || '' ) );
    my @switches;
    while ( my $opt = shift @opt ) {
        if ( $opt =~ /^ -I (.*) $ /x ) {
            push @libs, length($1) ? $1 : shift @opt;
        }
        else {
            push @switches, $opt;
        }
    }

    # Do things the old way on VMS...
    push @libs, _filtered_inc_vms() if IS_VMS;

    # If $Verbose isn't numeric default to 1. This helps core.
    my $verbose
      = $ENV{HARNESS_VERBOSE}
      ? $ENV{HARNESS_VERBOSE} !~ /\d/
          ? 1
          : $ENV{HARNESS_VERBOSE}
      : 0;

    my %args = (
        lib         => \@libs,
        timer       => $ENV{HARNESS_TIMER} || 0,
        switches    => \@switches,
        color       => $ENV{HARNESS_COLOR} || 0,
        verbosity   => $verbose,
        ignore_exit => $ENV{HARNESS_IGNORE_EXIT} || 0,
    );

    my $class = $input{harness_class} || $ENV{HARNESS_SUBCLASS} || 'TAP::Harness';
    if ( defined( my $env_opt = $ENV{HARNESS_OPTIONS} ) ) {
        for my $opt ( split /:/, $env_opt ) {
            if ( $opt =~ /^j(\d*)$/ ) {
                $args{jobs} = $1 || 9;
            }
            elsif ( $opt eq 'c' ) {
                $args{color} = 1;
            }
            elsif ( $opt =~ m/^f(.*)$/ ) {
                my $fmt = $1;
                $fmt =~ s/-/::/g;
                $args{formatter_class} = $fmt;
            }
            elsif ( $opt =~ m/^a(.*)$/ ) {
                my $archive = $1;
                $class = 'TAP::Harness::Archive';
                $args{archive} = $archive;
            }
            else {
                die "Unknown HARNESS_OPTIONS item: $opt\n";
            }
        }
    }
    return TAP::Object->_construct($class, { %args, %input });
}

1;

=head1 NAME

TAP::Harness::Env - Parsing harness related environmental variables where appropriate

=head1 VERSION

Version 3.31

=head1 SYNOPSIS

 my ($class, $args) = get_test_arguments();
 require_module($class);
 $class->new($args);

=head1 DESCRIPTION

This module implements the environmental variables that L<Test::Harness> for use with TAP::Harness.

=head1 FUNCTIONS

=over 4

=item * get_test_options( \%args )

This function reads the environment and generates an appropriate argument hash from it. If given any arguments, there will override the environmental defaults. It will return of C<$class> and C<$args>.

=back
