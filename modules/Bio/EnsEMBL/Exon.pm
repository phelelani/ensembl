#
# EnsEMBL module for Bio::EnsEMBL::Exon
#
#
# Copyright Ewan Birney
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=pod 

=head1 NAME Bio::EnsEMBL::Exon - A class representing an Exon

=head1 SYNOPSIS

    $ex = new Bio::EnsEMBL::Exon(-START     => 100,
                                 -END       => 200,
                                 -STRAND    => 1,
                                 -SLICE     => $slice,
                                 -DBID      => $dbID,
                                 -ANALYSIS  => $analysis,
                                 -STABLE_ID => 'ENSE000000123',
                                 -VERSION   => 2
                                 );

   #seq returns a Bio::Seq
   my $seq = $exon->seq->seq();

   #peptide only makes sense within transcript context
   my $pep = $exon->peptide($transcript)->seq();

   #normal feature operations can be performed:
   $exon = $exon->transform('clone');
   $exon->move($new_start, $new_end, $new_strand);
   print $exon->slice->seq_region_name();

=head1 DESCRIPTION

This is a class which represents an exon which is part of a transcript.
See Bio::EnsEMBL:Transcript

=head1 CONTACT

Post questions to the EnsEMBL developer list: <ensembl-dev@ebi.ac.uk>

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal
methods are usually preceded with a_

=cut

package Bio::EnsEMBL::Exon;
use vars qw(@ISA);
use strict;


use Bio::EnsEMBL::Feature;
use Bio::Seq; # exons have to have sequences...

use Bio::EnsEMBL::Utils::Exception qw( warning throw deprecate );
use Bio::EnsEMBL::Utils::Argument qw( rearrange );


@ISA = qw(Bio::EnsEMBL::Feature);


=head2 new

  Args       : see SUPERCLASS Bio::EnsEMBL::SeqFeature
  Example    : none
  Description: create an Exon object
  Returntype : Bio::EnsEMBL::Exon 
  Exceptions : none
  Caller     : general

=cut

sub new {
  my $class = shift;

  $class = ref $class || $class;

  my $self = $class->SUPER::new( @_ );

  my ( $phase, $end_phase, $stable_id, $version ) = 
    rearrange( [ "PHASE", "END_PHASE", "STABLE_ID", "VERSION" ], @_ );

  $self->{'phase'} = $phase;
  $self->{'end_phase'} = $end_phase;
  $self->{'stable_id'} = $stable_id;
  $self->{'version'} = $version;

  return $self;
}



=head2 new_fast

  Arg [1]    : Bio::EnsEMBL::Slice $slice
  Arg [2]    : int $start
  Arg [3]    : int $end
  Arg [4]    : int $strand (1 or -1)
  Example    : none
  Description: create an Exon object
  Returntype : Bio::EnsEMBL::Exon 
  Exceptions : none
  Caller     : general, creation in Bio::EnsEMBL::Lite::GeneAdaptor

=cut

sub new_fast {
  my ($class,$slice,$start,$end,$strand) = @_;

  my $self = bless {}, $class;

  # Swap start and end if they're in the wrong order
  # We assume that the strand is correct and keep the input value.

  if ($start > $end) {
    throw( "End smaller than start not allowed" );
  }

  $self->start ($start);
  $self->end   ($end);
  $self->strand($strand);
  $self->slice($slice);

  return $self;
}




=head2 end_phase

  Arg [1]    : (optional) int $end_phase
  Example    : $end_phase = $feat->end_phase;
  Description: Gets/Sets the end phase of the exon.
               end_phase = number of bases from the last incomplete codon of 
               this exon.
               Usually, end_phase = (phase + exon_length)%3
               but end_phase could be -1 if the exon is half-coding and its 3 
               prime end is UTR.
  Returntype : int
  Exceptions : warning if end_phase is called without an argument and the
               value is not set.
  Caller     : general

=cut

sub end_phase {
  my $self = shift;
  if( @_ ) { 
    $self->{'end_phase'} = shift;
  } else {
    if( ! defined ( $self->{'end_phase'} )) {
      warning( "No end phase set in Exon. You must set it explicitly." );
    }
  }
  return $self->{'end_phase'};
}




=pod

=head2 phase

  my $phase = $exon->phase;
  $exon->phase(2);

Get or set the phase of the Exon, which tells the
translation machinery, which makes a peptide from
the DNA, where to start.

The Ensembl phase convention can be thought of as
"the number of bases of the first codon which are
on the previous exon".  It is therefore 0, 1 or 2
(or -1 if the exon is non-coding).  In ascii art,
with alternate codons represented by B<###> and
B<+++>:

       Previous Exon   Intron   This Exon
    ...-------------            -------------...

    5'                    Phase                3'
    ...#+++###+++###          0 +++###+++###+...
    ...+++###+++###+          1 ++###+++###++...
    ...++###+++###++          2 +###+++###+++...

Here is another explanation from Ewan:

Phase means the place where the intron lands
inside the codon - 0 between  codons, 1 between
the 1st and second base, 2 between the second and
3rd  base. Exons therefore have a start phase and
a end phase, but introns have just one phase.

=cut

sub phase {
  my ($self,$value) = @_;
  
  if (defined($value)) {
    # Value must be 0,1,2, or -1 for non-coding
    if ($value =~ /^(-1|0|1|2)$/) {
      #print STDERR "Setting phase to $value\n";
      $self->{'phase'} = $value;
    } else {
      throw("Bad value ($value) for exon phase. Should only be" .
            " -1,0,1,2\n");
    }
  }
  return $self->{'phase'};
}



=head2 frame

  Arg [1]    : none
  Example    : $frame = $exon->frame
  Description: Gets the frame of this exon
  Returntype : int
  Exceptions : thrown if an arg is passed
               thrown if frame cannot be calculated due to a bad phase value
  Caller     : general

=cut

sub frame {
  my ($self,$value) = @_;

  if( defined $value ) {
    throw("Cannot set frame. Deduced from seq_start and phase");
  }

  # frame is mod 3 of the translation point

  if( $self->phase == -1 ) {
    return '.'; # gff convention for no frame info
  }
  if( $self->phase == 0 ) {
    return $self->start%3;
  }

  if( $self->phase == 1 ) {
    return ($self->start+2)%3;
  }

  if( $self->phase == 2 ) {
    return ($self->start+1)%3;
  }

  throw("bad phase in exon ".$self->phase);

}



=head2 type

  Arg [1]    : (optional) $value
  Example    : Gets/Sets th etype of this exon
  Description: Returns the type of the exon (Init, Intr, Term)
  Returntype : string
  Exceptions : none
  Caller     : ?

=cut

sub type {
  my ($self,$value) = @_;

  if (defined($value)) {
    $self->{'type'} = $value;
  }
  return $self->{'type'};
}



=head2 start

  Arg [1]    : int $start (optional)
  Example    : $start = $exon->start();
  Description: Getter/Setter for the start of this exon.  The superclass
               implmentation is overridden to flush the internal sequence
               cache if this value is altered
  Returntype : int
  Exceptions : none
  Caller     : general

=cut

sub start {
  my $self = shift;
  #if an arg was provided, flush the internal sequence cache
  delete $self->{'_seq_cache'} if(@_);
  return $self->SUPER::start(@_);
}


=head2 end

  Arg [1]    : int $end (optional)
  Example    : $end = $exon->end();
  Description: Getter/Setter for the end of this exon.  The superclass
               implmentation is overridden to flush the internal sequence
               cache if this value is altered
  Returntype : int
  Exceptions : none
  Caller     : general

=cut

sub end {
  my $self = shift;
  #if an arg was provided, flush the internal sequence cache
  delete $self->{'_seq_cache'} if(@_);
  return $self->SUPER::end(@_);
}


=head2 strand

  Arg [1]    : int $strand (optional)
  Example    : $start = $exon->strand();
  Description: Getter/Setter for the strand of this exon.  The superclass
               implmentation is overridden to flush the internal sequence
               cache if this value is altered
  Returntype : int
  Exceptions : none
  Caller     : general

=cut

sub strand {
  my $self = shift;
  #if an arg was provided, flush the internal sequence cache
  delete $self->{'_seq_cache'} if(@_);
  return $self->SUPER::strand(@_);
}


=head2 slice

  Arg [1]    : Bio::EnsEMBL::Slice
  Example    : $slice = $exon->slice();
  Description: Getter/Setter for the slice this exon is on.  The superclass
               implmentation is overridden to flush the internal sequence
               cache if this value is altered
  Returntype : Bio::EnsEMBL::Slice
  Exceptions : none
  Caller     : general

=cut

sub contig {
  my $self = shift;
  #if an arg was provided, flush the internal sequence cache
  delete $self->{'_seq_cache'} if(@_);
  return $self->SUPER::slice(@_);
}



=head2 move

  Arg [1]    : int start
  Arg [2]    : int end
  Arg [3]    : (optional) int strand
  Example    : None
  Description: Sets the start, end and strand in one call rather than in 
               3 seperate calls to the start(), end() and strand() methods.
               This is for convenience and for speed when this needs to be
               done within a tight loop.  This overrides the superclass
               move() method so that the internal sequence cache can be
               flushed if the exon if moved.
  Returntype : none
  Exceptions : Thrown is invalid arguments are provided
  Caller     : general

=cut

sub move {
  my $self = shift;
  #flush the internal sequence cache
  delete $self->{'_seq_cache'};
  return $self->SUPER::move(@_);
}



=head2 transform

  Arg  1     : String $coordinate_system_name
  Arg [2]    : String $coordinate_system_version
  Description: moves this exon to the given coordinate system. If this exon has
               attached supporting evidence, they move as well.
  Returntype : Bio::EnsEMBL::Exon
  Exceptions : wrong parameters
  Caller     : general

=cut


sub transform {
  my $self = shift;

  # catch for old style transform calls
  if( !@_  || ( ref $_[0] && $_[0]->isa( "Bio::EnsEMBL::Slice" ))) {
    deprecate('Calling transform without a coord system name is deprecated.');
    return $self->_deprecated_transform(@_);
  }

  my $new_exon = $self->SUPER::transform( @_ );
  return undef unless $new_exon;

  if( exists $self->{'_supporting_evidence'} ) {
    my @new_features;
    for my $old_feature ( @{$self->{'_supporting_evidence'}} ) {
      my $new_feature = $old_feature->transform( @_ );
      push( @new_features, $new_feature );
    }
    $new_exon->{'_supporting_evidence'} = \@new_features;
  }

  #dont want to share the same sequence cache
  delete $new_exon->{'_seq_cache'};

  return $new_exon;
}



=head2 transfer

  Arg [1]    : Bio::EnsEMBL::Slice $destination_slice
  Example    : none
  Description: Moves this Exon to given target slice coordinates. If Features
               are attached they are moved as well. Returns a new exon.
  Returntype : Bio::EnsEMBL::Gene
  Exceptions : none
  Caller     : general

=cut

sub transfer {
  my $self  = shift;

  my $new_exon = $self->SUPER::transfer( @_ );
  return undef unless $new_exon;

  if( exists $self->{'_supporting_evidence'} ) {
    my @new_features;
    for my $old_feature ( @{$self->{'_supporting_evidence'}} ) {
      my $new_feature = $old_feature->transfer( @_ );
      push( @new_features, $new_feature );
    }
    $new_exon->{'_supporting_evidence'} = \@new_features;
  }

  #dont want to share the same sequence cache
  delete $new_exon->{'_seq_cache'};

  return $new_exon;
}



=head2 add_supporting_features

  Arg [1]    : Bio::EnsEMBL::SeqFeatureI $feature
  Example    : $exon->add_supporting_features(@features);
  Description: Adds a list of supporting features to this exon. 
               Duplicate features are not added.  
               If supporting features are added manually in this
               way, prior to calling get_all_supporting_features then the
               get_all_supporting_features call will not retrieve supporting
               features from the database.
  Returntype : none
  Exceptions : throw if any of the features are not SeqFeatureIs
               throw if any of the features are not in the same coordinate
               system as the exon
  Caller     : general

=cut

sub add_supporting_features {
  my ($self,@features) = @_;
  #print STDERR "calling add supporting features\n\n";
  return unless @features;

  $self->{_supporting_evidence} ||= []; 
  
  # check whether this feature object has been added already
 FEATURE: foreach my $feature (@features) {
    #print STDERR "have ".$feature." to add to exon\n\n";
    unless($feature && $feature->isa("Bio::EnsEMBL::Feature")) {
      throw("Supporting feat [$feature] not a " .
            "Bio::EnsEMBL::Feature");
    } 
    
    if ((defined $self->slice() && defined $feature->slice())&&
	    ( $self->slice()->name() ne $feature->slice()->name())){
      throw("Supporting feat not in same coord system as exon\n" .
            "exon is attached to [".$self->slice()->name()."]\n" .
            "feat is attached to [".$feature->slice()->name()."]");
    }

    foreach my $added_feature ( @{ $self->{_supporting_evidence} } ){
      # compare objects
      if ( $feature == $added_feature ){
	#this feature has already been added
	next FEATURE;
      }
    }
    
    #no duplicate was found, add the feature
    push(@{$self->{_supporting_evidence}},$feature);
  }
}


=head2 get_all_supporting_features

  Arg [1]    : none
  Example    : @evidence = @{$exon->get_all_supporting_features()};
  Description: Retreives any supporting features added manually by 
               calls to add_supporting_features. If no features have been
               added manually and this exon is in a database (i.e. it h
  Returntype : listreference of Bio::EnsEMBL::BaseAlignFeature objects 
  Exceptions : none
  Caller     : general

=cut

sub get_all_supporting_features {
  my $self = shift;
  
  if( !exists  $self->{_supporting_evidence} )  {
    if($self->adaptor) {
      my $sfa = $self->adaptor->db->get_SupportingFeatureAdaptor();
      $self->{_supporting_evidence} = $sfa->fetch_all_by_Exon($self);
    } 
  }
  
  return $self->{_supporting_evidence} || [];
}


=head2 find_supporting_evidence

  Arg [1]    : Bio::EnsEMBL::SeqFeatureI $features
               The list of features to search for supporting (i.e. overlapping)
               evidence.
  Arg [2]    : (optional) boolean $sorted
               Used to speed up the calculation of overlapping features.  
               Should be set to true if the list of features is sorted in 
               ascending order on their start coordinates.
  Example    : $exon->find_supporting_evidence(\@features);
  Description: Looks through all the similarity features and
               stores as supporting features any feature
               that overlaps with an exon.  
  Returntype : none
  Exceptions : none
  Caller     : general

=cut

sub find_supporting_evidence {
  my ($self,$features,$sorted) = @_;

  foreach my $f (@$features) {
    # return if we have a sorted feature array
    if ($sorted == 1 && $f->start > $self->end) {
      return;
    }
    if ($f->sub_SeqFeature) {
      my @subf = $f->sub_SeqFeature;
      
      $self->find_supporting_evidence(\@subf);
    } 
    else {
      if ($f->entire_seq()->name eq $self->contig()->name) {
	if ($f->end >= $self->start && $f->start <= $self->end && $f->strand == $self->strand) {
	  $self->add_supporting_features($f);
	}
      }
    }
  }
}

=head2 stable_id

  Arg [1]    : string $stable_id
  Example    : none
  Description: get/set for attribute stable_id
  Returntype : string
  Exceptions : none
  Caller     : general

=cut

sub stable_id {
   my $self = shift;
  $self->{'stable_id'} = shift if( @_ );
  return $self->{'stable_id'};
}


=head2 version

  Arg [1]    : string $version
  Example    : none
  Description: get/set for attribute version
  Returntype : string
  Exceptions : none
  Caller     : general

=cut

sub version {
   my $self = shift;
  $self->{'version'} = shift if( @_ );
  return $self->{'version'};
}




=Head1 load_genomic_mapper

  Arg  1   : Bio::EnsEMBL::Mapper $mapper
             a mapper that will know how to go from cdna to genomic,
             after it is loaded here with the coordinates
  Arg  2   : int $id
             an id for the cdna, will probably be the address of the transcript
             that called this function. 

  Function : Loads the given mapper with cdna and genomic coordinates, so it can map 
             from one system to the other.

 Returntype: none
  Caller  : Bio::EnsEMBL::Transcript->convert_peptide_coordinate_to_contig


=cut


sub load_genomic_mapper {
  my ( $self, $mapper, $id, $start ) = @_;

  $mapper->add_map_coordinates( $id, $start, $start+$self->length()-1,
				$self->strand(), $self->slice(),
				$self->start(), $self->end() );
}



=head2 adjust_start_end

  Arg  1     : int $start_adjustment
  Arg  2     : int $end_adjustment
  Example    : none
  Description: returns a new Exon with this much shifted coordinates
  Returntype : Bio::EnsEMBL::Exon
  Exceptions : none
  Caller     : Transcript->get_all_translateable_Exons()

=cut

sub adjust_start_end {
  my ( $self, $start_adjust, $end_adjust ) = @_;

  my $new_exon = Bio::EnsEMBL::Exon->new();
  %{$new_exon} = %{$self};

  #invalidate the sequence cache
  delete $new_exon->{'_seq_cache'};

  if( $self->strand() == 1 ) {
    $new_exon->start( $self->start() + $start_adjust );
    $new_exon->end( $self->end() + $end_adjust )
  } else {
    $new_exon->start( $self->start() - $end_adjust );
    $new_exon->end( $self->end() - $start_adjust )
  }

  return $new_exon;
}


=head2 peptide

  Arg [1]    : Bio::EnsEMBL::Transcript $tr
  Example    : my $pep_str = $exon->peptide($transcript)->seq; 
  Description: Retrieves the portion of the transcripts peptide
               encoded by this exon.  The transcript argument is necessary
               because outside of the context of a transcript it is not
               possible to correctly determine the translation.  Note that
               an entire amino acid will be present at the exon boundaries
               even if only a partial codon is present.  Therefore the 
               concatenation of all of the peptides of a transcripts exons 
               is not the same as a transcripts translation because the 
               summation may contain duplicated amino acids at splice sites.
               In the case that this exon is entirely UTR, a Bio::Seq object 
               with an empty sequence string is returned.
  Returntype : Bio::Seq
  Exceptions : thrown if transcript argument is not provided
  Caller     : general

=cut

sub peptide {
  my $self = shift;
  my $tr = shift;

  unless($tr && ref($tr) && $tr->isa('Bio::EnsEMBL::Transcript')) {
    throw("transcript arg must be Bio::EnsEMBL:::Transcript not [$tr]");
  }

  #convert exons coordinates to peptide coordinates
  my $tmp_exon = $self->transfer($tr->slice);
  if (!$tmp_exon) {
    throw("Couldn't transfer exon to transcript's slice");
  }

  my @coords = 
    $tr->genomic2pep($tmp_exon->start, $tmp_exon->end, $tmp_exon->strand);
  
  #filter out gaps
  @coords = grep {$_->isa('Bio::EnsEMBL::Mapper::Coordinate')} @coords;

  #if this is UTR then the peptide will be empty string
  my $pep_str = '';

  if(scalar(@coords) > 1) {
    throw("Error. Exon maps to multiple locations in peptide." .
		 " Is this exon [$self] a member of this transcript [$tr]?");
  } elsif(scalar(@coords) == 1) {
    my $c = $coords[0];
    my $pep = $tr->translate;

    #bioperl doesn't give back residues for incomplete codons
    #make sure we don't subseq too far...
    my ($start, $end);
    $end = ($c->end > $pep->length) ? $pep->length : $c->end; 
    $start = ($c->start < $end) ? $c->start : $end;
    $pep_str = $tr->translate->subseq($start, $end);
  }
    
  return Bio::Seq->new(-seq => $pep_str, 
		       -moltype => 'protein',
		       -alphabet => 'protein',
                       -id => $self->stable_id);
}



=head2 seq

  Arg [1]    : none
  Example    : my $seq_str = $exon->seq->seq;
  Description: Retrieves the dna sequence of this Exon.  
               Returned in a Bio::Seq object.  Note that the sequence may
               include UTRs (or even be entirely UTR).
  Returntype : Bio::Seq
  Exceptions : warning if argument passed, warning if exon->contig not defined
  Caller     : general

=cut

sub seq {
  my $self = shift;
  my $arg = shift;

  if( defined $arg ) {
    warning( "seq setting on Exon not supported currently" );
    $self->{'_seq_cache'} = $arg->seq();
  }

  if( defined $self->{'_seq_cache'} ) {
    return Bio::Seq->new(-seq=> $self->{'_seq_cache'});
  }

  my $seq;

  if ( ! defined $self->slice ) {
    warning(" this exon doesn't have a slice you won't get a seq \n");
    return undef;
  }
  else {
      
    $seq = $self->slice()->subseq($self->start, $self->end);

    if($self->strand == -1){
      $seq =~ tr/ATGCatgc/TACGtacg/;
      $seq = reverse($seq);
    }
      
   }
  $self->{'_seq_cache'} = $seq;

  return Bio::Seq->new(-seq     => $self->{'_seq_cache'},
		       -id      => $self->stable_id,
		       -moltype => 'dna');
}




=head2 hashkey

  Arg [1]    : none
  Example    : if(exists $hash{$exon->hashkey}) { do_something(); }
  Description: Returns a unique hashkey that can be used to uniquely identify
               this exon.  Exons are considered to be identical if they share
               the same seq_region, start, end, strand, phase, end_phase.
               Note that this will consider two exons on different slices
               to be different, even if they actually are not. 
  Returntype : string formatted as slice_name-start-end-strand-phase-end_phase
  Exceptions : thrown if not all the necessary attributes needed to generate
               a unique hash value are set
               set
  Caller     : general

=cut

sub hashkey {
  my $self = shift;

  my $slice      = $self->{'slice'}; 
  my $slice_name = ($slice) ? $slice->name() : undef;
  my $start      = $self->{'start'};
  my $end        = $self->{'end'};
  my $strand     = $self->{'strand'};
  my $phase      = $self->{'phase'};
  my $end_phase  = $self->{'end_phase'};

  if(!defined($slice_name)) {
    throw('Slice must be set to generate correct hashkey.');
  }

  if(!defined($start)) {
    warning("start attribute must be defined to generate correct hashkey.");
  }

  if(!defined($end)) {
    throw("end attribute must be defined to generate correct hashkey.");
  }

  if(!defined($strand)) {
    throw("strand attribute must be defined to generate correct hashkey.");
  }

  if(!defined($phase)) {
    throw("phase attribute must be defined to generate correct hashkey.");
  }

  if(!defined($end_phase)) {
    throw("end_phase attribute must be defined to generate correct hashkey.");
  }

  return "$slice_name-$start-$end-$strand-$phase-$end_phase";
}


=head2 display_id

  Arg [1]    : none
  Example    : print $exons->display_id();
  Description: This method returns a string that is considered to be
               the 'display' identifier.  For exons this is the stable id if
               it is available otherwise it is an empty string.
  Returntype : string
  Exceptions : none
  Caller     : web drawing code

=cut

sub display_id {
  my $self = shift;
  return $self->{'stable_id'} || '';
}

#####################
# DEPRECATED METHODS
#####################


sub _get_stable_entry_info {
   my $self = shift;
   deprecate( "This function shouldnt be called any more" );
   if( !defined $self->adaptor ) {
     return undef;
   }
   $self->adaptor->get_stable_entry_info($self);
}


=head2 temporary_id

  Description: DEPRECATED.  This should not be necessary

=cut

sub temporary_id {
  my $self = shift;
  deprecate('It should not be necessary to use this method.');
  $self->{'tempID'} = shift if(@_);
  return $self->{'tempID'};
}

=head2 created

  Description: DEPRECATED.  Do not use.

=cut

sub created{
    my ($self,$value) = @_;
    deprecate( "Created attribute not supported any more" );
    if(defined $value ) {
      $self->{'_created'} = $value;
    }
    return $self->{'_created'};
}

=head2 modified

  Description: DEPRECATED.  Do not use.

=cut

sub modified{
    my ($self,$value) = @_;
    deprecate( "Modified attribute not supported any more" );
    if( defined $value ) {
      $self->{'_modified'} = $value;
    }
    return $self->{'_modified'};
}



1;
