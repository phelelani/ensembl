#
# BioPerl module for Bio::EnsEMBL::TimDB::Clone
#
# Cared for by Ewan Birney <birney@sanger.ac.uk>
#
# Copyright Ewan Birney
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::TimDB::Clone - Perl wrapper over Tim's directories for Clones

=head1 SYNOPSIS

    $clone = Bio::EnsEMBL::TimDB::Clone->new();
 
    $clone->add_Contig($contig);
    

=head1 DESCRIPTION

Describe the object here

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object
methods. Internal methods are usually preceded with a _

=cut

# Let the code begin...
package Bio::EnsEMBL::TimDB::Clone;
use vars qw($AUTOLOAD @ISA);
use strict;
use Bio::EnsEMBL::DB::CloneI;
use Bio::EnsEMBL::TimDB::Contig;

# Object preamble - inheriets from Bio::Root::Object
use Bio::Root::Object;

@ISA = qw(Bio::Root::Object Bio::EnsEMBL::DB::CloneI);
# new() is inherited from Bio::Root::Object

# _initialize is where the heavy stuff will happen when new is called
sub _initialize {
  my($self,@args) = @_;
  my $make = $self->SUPER::_initialize(@args);

  # set stuff in self from @args
  my ($dbobj,$id,$cgp,$disk_id,$sv,$emblid,$htgsp)=
      $self->_rearrange([qw(DBOBJ
			    ID
			    CGP
			    DISK_ID
			    SV
			    EMBLID
			    HTGSP
			    )],@args);
  $id || $self->throw("Cannot make contig db object without id");
  $disk_id || $self->throw("Cannot make contig db object without disk_id");
  $dbobj || $self->throw("Cannot make contig db object without db object");
  $dbobj->isa('Bio::EnsEMBL::TimDB::Obj') || 
      $self->throw("Cannot make contig db object with a $dbobj object");
  $cgp || $self->throw("Cannot make a contig db object without location data");

  # id of clone
  $self->id($id);
  $self->disk_id($disk_id);
  $self->sv($sv);
  $self->embl_id($emblid);
  $self->htg_phase($htgsp);
  # db object
  $self->_dbobj($dbobj);

  # construct and test the directory of the clone
  my $clone_dir=$dbobj->{'_unfinished_root'}."/$cgp/data/$disk_id";
  unless(-d $clone_dir){
      $self->throw("Cannot find directory for $disk_id");
  }
  $self->{'_clone_dir'}=$clone_dir;

  # check for sequence file
  if(!-e "$clone_dir/$disk_id.seq"){
      $self->throw("Error: no sequence file for entry $id ($disk_id)");
  }

  # build list of contigs for clone
  # (methods get_all_Contigs and get_Contig look at this list of objects, 
  # rather than build it)
  # FIXME
  # THERE IS CURRENTLY NO QUICK WAY TO LOOK THIS UP!!!
  # getting a list of contigs is currently horrible.  There is a list in the
  # relevant dbm file, however this has to be stepped though.  There
  # is a list in the relevant clone.seq file (headers) except when this file is 
  # absent.  There should be a .gs file for each contig.

  # open dbm for this clone (to check contigs are listed there)
  my $contig_dbm_file=$dbobj->{'_unfinished_root'}."/$cgp/unfinished_ana.dbm";
  my %unfin_contig;
  unless(dbmopen(%unfin_contig,$contig_dbm_file,0666)){
      $self->throw("Error opening contig dbm file");
  }
  my($key,$val);
  my @contig_id;
  while(($key,$val)=each %unfin_contig){
      if($key=~/^$disk_id/){
	  push(@contig_id,$key);
	  # check for gs file
	  if(!-e "$clone_dir/$key.gs"){
	      $self->throw("Error: no gs file for contig $key");
	  }
      }
  }
  my @res;
  foreach my $contig_id (@contig_id){
      my $disk_contig_id=$contig_id;
      if($dbobj->{'_byacc'}){
	  $contig_id=~s/^$disk_id/$id/;
      }
      my $contig = new Bio::EnsEMBL::TimDB::Contig ( -dbobj => $self->_dbobj,
						     -cloneobj => $self,
						     -id => $contig_id,
						     -disk_id => $disk_contig_id,
						     );
      push(@res,$contig);
  }
  $self->{'_contig_array'}=\@res;

  # DEBUG
  print STDERR scalar(@{$self->{'_contig_array'}})." contigs found in clone\n";

  return $make; # success - we hope!
}


=head2 get_all_Contigs

 Title   : get_all_Contigs
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :

=cut

sub get_all_Contigs{
   my ($self) = @_;
   return @{$self->{'_contig_array'}};
}


=head2 get_Contig

 Title   : get_Contig
 Usage   :
 Function:
 Example :
 Returns : contig object
 Args    : contig_id

=cut

sub get_Contig {
    my ($self,$contigid) = @_;
    my $c;
    foreach my $contig (@{$self->{'_contig_array'}}){
	if( $contigid eq $contig->id()){
	    $c=$contig;
	    last;
	}
    }
    unless($c){
	$self->throw("contigid $contigid not found in this clone");
    }
    return $c;
}


=head2 add_Contig

 Title   : add_Contig
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :

=cut

sub add_Contig{
   my ($self,$contig) = @_;
   $self->throw("Cannot add items to TimDB");
}


=head2 get_all_Genes

 Title   : get_all_Genes
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :

=cut

sub get_all_Genes{
    my ($self) = @_;
    my %h;
    
    # loop over contigs, then loop over genes
    foreach my $contig ($self->get_all_Contigs) {
	foreach my $gene ($contig->get_all_Genes){
	    # read into a hash to make unique
	    $h{$gene->id()} = $gene;
       }
    }
    # DEBUG
    print STDERR "Clone contains ".scalar(keys %h)." genes\n";
    return values %h;
}

#
# Seq method from the cloneI object now
#


=head2 id

 Title   : id
 Usage   : $obj->id($newval)
 Function: 
 Example : 
 Returns : value of id
 Args    : newvalue (optional)

=cut

sub id {
    my ($obj,$value) = @_;
    if( defined $value) {
	$obj->{'_clone_id'} = $value;
    }
    return $obj->{'_clone_id'};
}


sub disk_id {
    my ($obj,$value) = @_;
    if( defined $value) {
	$obj->{'_clone_disk_id'} = $value;
    }
    return $obj->{'_clone_disk_id'};
}


=head2 _dbobj

 Title   : _dbobj
 Usage   : $obj->_dbobj($newval)
 Function: 
 Example : 
 Returns : value of _dbobj
 Args    : newvalue (optional)

=cut

sub _dbobj {
    my ($obj,$value) = @_;
    if( defined $value) {
	$obj->{'_dbobj'} = $value;
    }
    return $obj->{'_dbobj'};
}

=head2 embl_id

 Title   : embl_id
 Usage   : this is the embl_id for this clone, to generate nice looking files
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub embl_id {
    my ($obj,$value) = @_;
    if( defined $value) {

	# FIXME
	# may be '' - what to do in this case?

	$obj->{'_clone_embl_id'} = $value;
    }
    return $obj->{'_clone_embl_id'};
}


=head2 sv

 Title   : sv
 Function: returns the version number (not the acc.version, just verision).
 Example :
 Returns : 
 Args    :


=cut

sub sv {
    my ($obj,$value) = @_;
    if( defined $value) {
	if($value=~/^\d+$/){
	    $obj->{'_clone_sv'} = $value;
	}else{
	    $obj->throw("Invalid value for SV $value");
	}
    }
    return $obj->{'_clone_sv'};
}


=head2 htg_phase

 Title   : htg_phase
 Usage   : this is the phase being 0,1,2,3,4 (4 being finished).
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub htg_phase {
    my ($obj,$value) = @_;
    if( defined $value) {
	if($value=~/^[01234]$/){
	    $obj->{'_clone_htgsp'} = $value;
	}else{
	    $obj->throw("Invalid value for htg_phase $value");
	}
    }
    return $obj->{'_clone_htgsp'};
}


1;
