# Bio::EnsEMBL::Utils::Converter::bio_ens_gene
#
# Created and cared for by Juguang Xiao <juguang@tll.org.sg>
# Created date: 26/3/2003
# 
# Copyright Juguang Xiao
# 
# You may distribute this module under the same terms as perl itself
#
# POD documentation
#

=head1 NAME

Bio::EnsEMBL::Utils::Converter::bio_ens_gene

=head1 SYNOPISIS



=head1 DESCRIPTION

This module is to convert from objects of Bio::SeqFeature::Gene::GeneStructure
to those of Bio::EnsEMBL::Gene

=head1 FEEDBACK

=head2 Mailing Lists

=head2 Reporting Bugs


=head1 AUTHOR Juguang Xiao

Juguang Xiao <juguang@tll.org.sg>

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

# Let the code begin ...

package Bio::EnsEMBL::Utils::Converter::bio_ens_gene;

use strict;
use vars qw(@ISA);
use Bio::EnsEMBL::Utils::Converter;
@ISA = qw(Bio::EnsEMBL::Utils::Converter);

sub _initialize {
    my ($self, @args) = @_;
    my $converter_for_transcripts = new Bio::EnsEMBL::Utils::Converter(
        -in => 'Bio::SeqFeature::Gene::Transcript',
        -out => 'Bio::EnsEMBL::Transcript'
    );

    $self->_converter_for_transcripts($converter_for_transcripts);
}

sub _convert_single {
    my ($self, $input) = @_;

    unless($input->isa('Bio::SeqFeature::Gene::GeneStructure')){
        $self->throw("a Bio::SeqFeature::Gene::GeneStructure object needed");
    }
    my $gene = $input;
    my $ens_gene = Bio::EnsEMBL::Gene->new();
    my @transcripts = $gene->transcripts;
    
    # 
    $self->_converter_for_transcripts->contig($self->contig);
    
    my $ens_transcripts = $self->_converter_for_transcripts->convert(
        \@transcripts);
    
    foreach(@{$ens_transcripts}){
        $ens_gene->add_Transcript($_);
    }
    return $ens_gene;
}

=head2 _converter_for_transcripts
  Title   : _converter_for_transcripts
  Usage   : $self->_converter_for_transcripts
  Function: get and set for _converter_for_transcripts
  Return  : L<Bio::EnsEMBL::Utils::Converter>
  Args    : L<Bio::EnsEMBL::Utils::Converter>
  Notes   : This is for internal use. Do not sign it.
=cut

sub _converter_for_transcripts {
    my ($self, $arg) = @_;
    if(defined($arg)){
        $self->throws("A Bio::EnsEMBL::Utils::Converter object expected.") unless($arg->isa('Bio::EnsEMBL::Utils::Converter'));
        $self->{__converter_for_transcripts} = $arg;
    }
    return $self->{__converter_for_transcripts};
}

1;
