# POD documentation - main docs before the code

=head1 NAME

GenOO::Region - Role that represents a region on a reference sequence

=head1 SYNOPSIS

    This role when consumed requires specific attributes and provides
    methods that correspond to a region on a reference sequence.

=head1 DESCRIPTION

    A region object is an area on another reference sequence. It has a
    specific start and stop position on the reference and a specific 
    direction (strand). It has methods that combine the direction with
    the positional information a give positions for the head or the tail
    of the region. It also offers methods that calculate distances or
    overlaps with other object that also consume the role.

=head1 EXAMPLES

    # Get the location information on the reference sequence
    $obj_with_role->start;   # 10
    $obj_with_role->stop;    # 20
    $obj_with_role->strand;  # -1
    
    # Get the head position on the reference sequence
    $obj_with_role->head_position;  # 20

=cut

# Let the code begin...

package GenOO::Data::File::SAM::Cigar;


#######################################################################
#######################   Load External modules   #####################
#######################################################################
use Moose::Role;
use namespace::autoclean;


#######################################################################
########################   Required attributes   ######################
#######################################################################
requires qw(cigar strand start);


#######################################################################
########################   Interface Methods   ########################
#######################################################################
sub insertion_count {
	my ($self) = @_;
	
	my $cigar = $self->cigar;
	
	my $insertion_count = 0;
	while ($cigar =~ /(\d)I/g) {
		$insertion_count += $1;
	}
	return $insertion_count;
}

sub deletion_count {
	my ($self) = @_;
	
	my $cigar = $self->cigar;
	
	my $deletion_count = 0;
	while ($cigar =~ /(\d)D/g) {
		$deletion_count += $1;
	}
	return $deletion_count;
}

sub deletion_positions_on_query {
	my ($self) = @_;
	#Tag:    AGTGATGGGA------GGATGTCTCGTCTGTGAGTTACAGCA -> CIGAR: 2M1I7M6D26M
	#            -   -
	#Genome: AG-GCTGGTAGCTCAGGGATGTCTCGTCTGTGAGTTACAGCA -> MD:Z:  3C3T1^GCTCAG26
	
	my @deletion_positions;
	if ($self->cigar =~ /D/) {
		my $cigar = $self->cigar_relative_to_query;
		
		my $relative_position = 0;
		while ($cigar =~ /(\d+)([A-Z])/g) {
			my $count = $1;
			my $identifier = $2;
			
			if ($identifier eq 'D') {
				push @deletion_positions, $relative_position;
			}
			else {
				$relative_position += $count;
			}
		}
	}
	
	return @deletion_positions;
}

sub insertion_positions_on_query {
	my ($self) = @_;
	#Tag:    AGTGATGGGA------GGATGTCTCGTCTGTGAGTTACAGCA -> CIGAR: 2M1I7M6D26M
	#            -   -
	#Genome: AG-GCTGGTAGCTCAGGGATGTCTCGTCTGTGAGTTACAGCA -> MD:Z:  3C3T1^GCTCAG26
	
	my @insertion_positions;
	if ($self->cigar =~ /I/) {
		my $cigar = $self->cigar_relative_to_query;
		
		my $relative_position = 0;
		while ($cigar =~ /(\d+)([A-Z])/g) {
			my $count = $1;
			my $identifier = $2;
			
			if ($identifier eq 'I') {
				push @insertion_positions, $relative_position;
			}
			else {
				$relative_position += $count;
			}
		}
	}
	
	return @insertion_positions;
}

sub cigar_relative_to_query {
	my ($self) = @_;
	
	my $cigar = $self->cigar;
	
	# if negative strand -> reverse the cigar string
	if (defined $self->strand and ($self->strand == -1)) {
		my $reverse_cigar = '';
		while ($cigar =~ /(\d+)([A-Z])/g) {
			$reverse_cigar = $1.$2.$reverse_cigar;
		}
		return $reverse_cigar;
	}
	else {
		return $cigar;
	}
}

1;
