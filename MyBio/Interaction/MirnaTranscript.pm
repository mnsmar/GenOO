package MyBio::Interaction::MirnaTranscript;

# Corresponds to the interaction between a miRNA and a transcript.
# Each such object contains multiple binding sites (MREs) that correspond to the available transcript regions (5'UTR, CDS or 3'UTR)

use strict;
use PerlIO::gzip;

use MyBio::DBconnector;
use MyBio::Transcript;
use MyBio::MyMath;
use MyBio::Mirna::Mimat;
use MyBio::Interaction::MirnaUTR5;
use MyBio::Interaction::MirnaCDS;
use MyBio::Interaction::MirnaUTR3;

use base qw(MyBio::_Initializable);

# HOW TO INITIALIZE THIS OBJECT
# my $interaction = Target::MirnaTranscriptInteraction->new({
# 		     TRANSCRIPT     => undef, #Transcript
# 		     MIRNA          => undef, #Mirna::Mimat
# 		     MRES           => [],
# 		     SCORE          => undef,
# 		     SNR            => undef,
# 		     PRECISION      => undef,
# 		     EXTRA_INFO     => undef,
# 		     });

sub _init {
	my ($self,$data) = @_;
	
	$self->{TRANSCRIPT}   = $$data{TRANSCRIPT}; #MyBio::Transcript
	$self->{MIRNA}        = $$data{MIRNA}; #MyBio::Mirna::Mimat
	$self->{MRES}         = $$data{MRES};  #[]
	$self->{SCORE}        = $$data{SCORE};
	$self->{SNR}          = $$data{SNR};
	$self->{PRECISION}    = $$data{PRECISION};
	$self->{EXTRA_INFO}   = $$data{EXTRA_INFO};
	
	return $self;
}

#######################################################################
#############################   Getters   #############################
#######################################################################
sub get_transcript {return $_[0]->{TRANSCRIPT};}
sub get_mirna      {return $_[0]->{MIRNA};}
sub get_snr        {return $_[0]->{SNR};}
sub get_precision  {return $_[0]->{PRECISION};}
sub get_extra      {return $_[0]->{EXTRA_INFO};}
sub get_mres {
	if (defined $_[1]) {
		return ${$_[0]->{MRES}}[$_[1]]; #return the requested element
	}
	else {
		return $_[0]->{MRES}; #return the reference to the array
	}
}
sub get_score      {
	my ($self) = @_;
	unless (defined $self->{SCORE}) {
		$self->{SCORE} = $self->calculate_score_for_version_5_0();
	}
	return $self->{SCORE};
}

#######################################################################
#############################   Setters   #############################
#######################################################################
sub set_mirna { $_[0]->{MIRNA} = $_[1] if defined $_[1];}
sub set_score { $_[0]->{SCORE} = $_[1] if defined $_[1];}
sub set_extra { $_[0]->{EXTRA_INFO} = $_[1] if defined $_[1];}

#######################################################################
#########################   General Methods   #########################
#######################################################################
sub push_mre {
	push (@{$_[0]->{MRES}},$_[1]) if defined $_[1];
}
sub get_number_of_mres_below_category {
	my ($self,$category) = @_;
	
	my $counter = 0;
	if (defined $category) {
		foreach my $mre (@{$self->{MRES}}) {
			if ($mre->get_category() < $category) {
				$counter++;
			}
		}
	}
	return $counter;
}
sub calculate_score_for_version_5_0 {
	my ($self) = @_;
	
	my $intercept = -0.65503;
	my $weight1 = 20.97570;
	my $weight2 = 61.18472;
	my $weight3 = -327.97649;
	my $CDSscore = 0;
	my $UTR3score = 0;
	my @MREs = @{$self->get_mres()};
	foreach my $mre (@MREs) {
		if ($mre->get_where eq 'CDS') {
			$CDSscore += $mre->get_mre_score('5.0');
		}
		elsif ($mre->get_where eq 'UTR3') {
			$UTR3score += $mre->get_mre_score('5.0');
		}
	}
	
	if ($CDSscore == 0 and $UTR3score == 0) {
		return 0;
	}
	else {
		my $totalScore = $weight1*$CDSscore + $weight2*$UTR3score + $weight3*$CDSscore*$UTR3score + $intercept;
		return MyBio::MyMath->sigmoid($totalScore);
	}
}

#######################################################################
##########################   Class Methods   ##########################
#######################################################################
{
	sub read_interactions {
		my ($class,$method,@attributes) = @_;
		
		my %interactions;
		
		if ($method eq "FILE") {
			my $filename = $attributes[0];
			%interactions = $class->_read_file_with_interactions($filename);
		}
		elsif ($method eq "OLDFILE") {
			my $filename = $attributes[0];
			my $miTG_score_threshold = $attributes[1];
			my $mre_thres = $attributes[2];
			%interactions = $class->_read_oldfile_with_interactions($filename,$miTG_score_threshold,$mre_thres);
		}
		
		return %interactions;
	}
	
	sub _read_file_with_interactions {
		my ($class,$file) = @_;
		
		my %interactions;
		my $interaction;
		my $fileReadType = "<"; 
		if ($file =~ /\.gz$/) {$fileReadType = "<:gzip"}
		
		open (my $IN,$fileReadType,$file) or die "Cannot open file $file: $!";
		while (my $line = <$IN>) {
			chomp($line);
			if (substr($line,0,1) eq '>') {
				$line = substr($line,1);
				my ($mirnaName,$enstid,$score,@extra)=split(/\|/,$line);
				
				# check if the corresponding Transcript and Mirna objects exist
				my $mirna = MyBio::Mirna::Mimat->get_by_name($mirnaName);
				unless (defined $mirna) {
					$mirna = MyBio::Mirna::Mimat->new({NAME => $mirnaName});
				}
				my $transcript = MyBio::Transcript->get_by_enstid($enstid);
				unless (defined $transcript) {
					$transcript = MyBio::Transcript->new({ENSTID => $enstid});
				}
				
				$interaction = $class->new({
							TRANSCRIPT     => $transcript,
							MIRNA          => $mirna,
							SCORE          => $score,
							EXTRA_INFO     => join("|",@extra),
							});
				$interactions{$interaction->get_mirna->get_name()}{$interaction->get_transcript->get_enstid()} = $interaction;
			}
			elsif (substr($line,0,1) ne "#") {
				my ($where,$mirnaName,$enstid,$position,$dif1,$dif2,$categoryNum,$first_binding_nt,$bindingVector,$RNAhybrid,$energyPercentage,$conservation,$mre_score,@mreExtra) = split(/\t/,$line);
				
				my %data = (
						MIRNA_TRANSCRIPT_INTERACTION => $interaction,
						WHERE             => $where,
						CATEG             => $categoryNum,
						POS_ON_REGION     => $position,
						DIF1              => $dif1,
						DIF2              => $dif2,
						FIRST_BINDING     => $first_binding_nt,
						BINDING_VECTOR    => $bindingVector,
						RNAHYBRID         => $RNAhybrid,
						ENERGY_PERCENTAGE => $energyPercentage,
						CONSERVATION      => $conservation,
						MRE_SCORE         => $mre_score,
						EXTRA_INFO        => join('|',@mreExtra),
						);
				
				if ($where eq 'CDS') {
					my $mreObj = MyBio::Interaction::MirnaCDS->new(\%data);
				}
				elsif ($where eq 'UTR3') {
					my $mreObj = MyBio::Interaction::MirnaUTR3->new(\%data);
				}
				elsif ($where eq 'UTR5') {
					my $mreObj = MyBio::Interaction::MirnaUTR5->new(\%data);
				}
			}
		}
		close $IN;
		
		return %interactions;
	}
	
	sub _read_oldfile_with_interactions {
		my ($class,$file,$miTG_score_threshold,$mre_thres) = @_;
		
		my %interactions;
		my $interaction;
		my $transcript;
		my $useInteraction;
		my $score;
		my $precision;
		my $snr;
		
		my $fileReadType = ($file =~ /\.gz$/) ? "<:gzip" : "<"; 
		open (my $IN,$fileReadType,$file) or die "Cannot open file $file: $!";
		while (my $line = <$IN>) {
			chomp($line);
			if ($line =~ /^>/) {
				$useInteraction = undef;
				$interaction = undef;
				$score = undef;
				
				my ($chr,$ensg,$name,$strand,$splice_starts,$splice_stops,$enstid,$conservation,$miTGscore,$prec,$ratio) = split(/\|/,$line);
				$chr =~ s/>//g;
				
				if ($miTGscore >= $miTG_score_threshold) {
					$useInteraction = 1;
					$score = $miTGscore;
					$precision = $prec;
					$snr = $ratio;
					
					# check if the corresponding Transcript exists
					$transcript = MyBio::Transcript->get_by_enstid($enstid);
					unless (defined $transcript) {
						$transcript = MyBio::Transcript->new({
							CHR              => $chr,
							ENSTID           => $enstid,
							ENSGID           => $ensg,
							COMMON_NAME      => $name,
							STRAND           => $strand,
							SPLICE_STARTS    => $splice_starts,
							SPLICE_STOPS     => $splice_stops,
						});
					}
				}
			}
			elsif (($line !~ /^#/) and ($useInteraction)) {
				my ($mirnaName,$seedStart,$seedStop,$dif1,$dif2,$categoryNum,$first_binding_nt,$MRE_start,$MRE_stop,$bindingVector,$RNAhybrid,$NA,$NA2,$energyPercentage,$conservationVector,$access_r1,$access_r2,$access_r3,$access_r4,$MREscore) = split(/\|/,$line);
				if ($MREscore > $mre_thres) {
					# check if the corresponding miRNA objects exists
					my $mirna = MyBio::Mirna::Mimat->get_by_name($mirnaName);
					unless (defined $mirna) {
						$mirna = MyBio::Mirna::Mimat->new({NAME => $mirnaName});
					}
					
					# create the interaction if it has not already been created
					unless (defined $interaction) {
						$interaction = $class->new({
								TRANSCRIPT     => $transcript,
								MIRNA          => $mirna,
								SCORE          => $score,
								SNR            => $snr,
								PRECISION      => $precision,
								});
						$interactions{$interaction->get_mirna->get_name()}{$interaction->get_transcript->get_enstid()} = $interaction;
					}
					
					my $mreObj = MyBio::Interaction::MirnaUTR3->new({
						MIRNA_TRANSCRIPT_INTERACTION => $interaction,
						WHERE             => "UTR3",
						CATEG             => $categoryNum,
						POS_ON_REGION     => $seedStop,
						DIF1              => $dif1,
						DIF2              => $dif2,
						FIRST_BINDING     => $first_binding_nt,
						BINDING_VECTOR    => $bindingVector,
						RNAHYBRID         => $RNAhybrid,
						ENERGY_PERCENTAGE => $energyPercentage,
						CONSERVATION      => $conservationVector,
						MRE_SCORE         => $MREscore,
# 						EXTRA_INFO        => join('|',@mreExtra),
					});

					
				}
			}
		}
		close $IN;
		
		return %interactions;;
	}
	
	
# 	sub read_predicted_interactions_from_workFolder {
# 		my ($class,$workFolder,$predictionsFilename)=@_;
# 		
# 		my $predictionsFile = $workFolder."/".$predictionsFilename;
# 		my $miRNAfile       = $workFolder."/miRNA.dat";
# 		my $mirnaObj = MyBio::Mirna::Mimat->read_Mimat_from_file($miRNAfile);
# 		$class->read_fasta_file_to_hash_of_interaction_objects($predictionsFile,$mirnaObj);
# 			
# 		return %allInteractions;
# 	}
	
}

1;