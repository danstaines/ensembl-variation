=head1 LICENSE

 Copyright (c) 1999-2011 The European Bioinformatics Institute and
 Genome Research Limited.  All rights reserved.

 This software is distributed under a modified Apache license.
 For license details, please see

   http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

 Please email comments or questions to the public Ensembl
 developers list at <dev@ensembl.org>.

 Questions may also be sent to the Ensembl help desk at
 <helpdesk@ensembl.org>.

=cut

# Ensembl module for Bio::EnsEMBL::Variation::Variation
#
# Copyright (c) 2004 Ensembl
#


=head1 NAME

Bio::EnsEMBL::Variation::Variation - Ensembl representation of a nucleotide variation.

=head1 SYNOPSIS

    $v = Bio::EnsEMBL::Variation::Variation->new(-name   => 'rs123',
                                                 -source => 'dbSNP');

    # add additional synonyms for the same SNP
    $v->add_synonym('dbSNP', 'ss3242');
    $v->add_synonym('TSC', '53253');

    # add some validation states for this SNP
    $v->add_validation_status('freq');
    $v->add_validation_status('cluster');

    # add alleles associated with this SNP
    $a1 = Bio::EnsEMBL::Allele->new(...);
    $a2 = Bio::EnsEMBL::Allele->new(...);
    $v->add_Allele($a1);
    $v->add_Allele($a2);

    # set the flanking sequences
    $v->five_prime_flanking_seq($seq);
    $v->three_prime_flanking_seq($seq);


    ...

    # print out the default name and source of the variation and the version
    print $v->source(), ':',$v->name(), ".",$v->version,"\n";

    # print out every synonym associated with this variation
    @synonyms = @{$v->get_all_synonyms()};
    print "@synonyms\n";

    # print out synonyms and their database associations
    my $sources = $v->get_all_synonym_sources();
    foreach my $src (@$sources) {
      @synonyms = $v->get_all_synonyms($src);
      print "$src: @synonyms\n";
    }


    # print out validation states
    my @vstates = @{$v->get_all_validation_states()};
    print "@validation_states\n";

    # print out flanking sequences
    print "5' flanking: ", $v->five_prime_flanking_seq(), "\n";
    print "3' flanking: ", $v->three_prime_flanking_seq(), "\n";


=head1 DESCRIPTION

This is a class representing a nucleotide variation from the
ensembl-variation database. A variation may be a SNP a multi-base substitution
or an insertion/deletion.  The objects Alleles associated with a Variation
object describe the nucleotide change that Variation represents.

A Variation object has an associated identifier and 0 or more additional
synonyms.  The position of a Variation object on the Genome is represented
by the B<Bio::EnsEMBL::Variation::VariationFeature> class.

=head1 METHODS

=cut


use strict;
use warnings;

package Bio::EnsEMBL::Variation::Variation;

use Bio::EnsEMBL::Storable;
use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Utils::Scalar qw(assert_ref);
use Bio::EnsEMBL::Variation::Utils::Sequence qw(ambiguity_code SO_variation_class);
use Bio::EnsEMBL::Utils::Exception qw(throw deprecate warning);
use Bio::EnsEMBL::Variation::Utils::Sequence;
use Bio::EnsEMBL::Variation::Utils::Constants qw(%VARIATION_CLASSES); 

use vars qw(@ISA);
use Scalar::Util qw(weaken);

@ISA = qw(Bio::EnsEMBL::Storable);

=head2 new

  Arg [-dbID] :
    int - unique internal identifier for snp

  Arg [-ADAPTOR] :
    Bio::EnsEMBL::Variation::DBSQL::VariationAdaptor
    Adaptor which provides database connectivity for this Variation object

  Arg [-NAME] :
    string - the name of this SNP

  Arg [-SOURCE] :
    string - the source of this SNP	

  Arg [-SOURCE_DESCRIPTION] :
    string - description of the SNP source
		
	Arg [-SOURCE_TYPE] :
		string - the source type of this variant

  Arg [-SYNONYMS] :
    reference to hash with list reference values -  keys are source
    names and values are lists of identifiers from that db.
    e.g.: {'dbSNP' => ['ss1231', '1231'], 'TSC' => ['1452']}

  Arg [-ANCESTRAL_ALLELES] :
    string - the ancestral allele of this SNP

  Arg [-ALLELES] :
    reference to list of Bio::EnsEMBL::Variation::Allele objects

  Arg [-VALIDATION_STATES] :
    reference to list of strings

  Arg [-MOLTYPE] :
    string - the moltype of this SNP

  Arg [-FIVE_PRIME_FLANKING_SEQ] :
    string - the five prime flanking nucleotide sequence

  Arg [-THREE_PRIME_FLANKING_SEQ] :
    string - the three prime flanking nucleotide sequence

  Example    : $v = Bio::EnsEMBL::Variation::Variation->new
                    (-name   => 'rs123',
                     -source => 'dbSNP');

  Description: Constructor. Instantiates a new Variation object.
  Returntype : Bio::EnsEMBL::Variation::Variation
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut


sub new {
  my $caller = shift;
  my $class = ref($caller) || $caller;

  my ($dbID, $adaptor, $name, $class_so_term, $src, $src_desc, $src_url, $src_type, $is_somatic, $syns, $ancestral_allele,
      $alleles, $valid_states, $moltype, $five_seq, $three_seq, $flank_flag) =
        rearrange([qw(dbID ADAPTOR NAME CLASS_SO_TERM SOURCE SOURCE_DESCRIPTION SOURCE_URL SOURCE_TYPE IS_SOMATIC 
                      SYNONYMS ANCESTRAL_ALLELE ALLELES VALIDATION_STATES MOLTYPE FIVE_PRIME_FLANKING_SEQ
                      THREE_PRIME_FLANKING_SEQ FLANK_FLAG)],@_);

  # convert the validation state strings into a bit field
  # this preserves the same order and representation as in the database
  # and filters out invalid states
  my $vcode = Bio::EnsEMBL::Variation::Utils::Sequence::get_validation_code($valid_states);
  
  my $self = bless {
    'dbID' => $dbID,
    'adaptor' => $adaptor,
    'name'   => $name,
    'class_SO_term' => $class_so_term,
    'source' => $src,
    'source_description' => $src_desc,
    'source_url' => $src_url,
	'source_type'=> $src_type,
    'is_somatic' => $is_somatic,
    'synonyms' => $syns || {},
    'ancestral_allele' => $ancestral_allele,
    'validation_code' => $vcode,
    'moltype' => $moltype,
    'five_prime_flanking_seq' => $five_seq,
    'three_prime_flanking_seq' => $three_seq,
    'flank_flag' => $flank_flag
  }, $class;
  
    # Add the alleles to this Variation object
    map {$self->_add_Allele($_)} @{$alleles} if (defined($alleles));
  
  return $self;
}


=head2 is_failed

  Example    : print "Variation '" . $var->name() . "' has " . ($var->is_failed() ? "" : "not ") . "been flagged as failed\n";
  Description: Gets the failed attribute for this variation. The failed attribute
	           is lazy-loaded from the database.
  Returntype : int
  Exceptions : none
  Caller     : general
  Status     : At risk

=cut

sub is_failed {
  my $self = shift;
  
  return (length($self->failed_description()) > 0);
}

=head2 has_failed_subsnps

  Description: DEPRECATED: Use has_failed_alleles instead.
  Status     : DEPRECATED

=cut

sub has_failed_subsnps {
    my $self = shift;
  
    deprecate("has_failed_subsnps should no longer be used, use has_failed_alleles instead\n");
    return $self->has_failed_alleles();
}

=head2 has_failed_alleles

  Example    : print "Variation '" . $var->name() . "' has " . ($var->has_failed_alleles() ? "" : "no ") . " failed alleles\n";
  Description: Returns true if this variation has alleles that are flagged as failed
  Returntype : int
  Exceptions : none
  Caller     : general
  Status     : At risk

=cut

sub has_failed_alleles {
    my $self = shift;
  
    map {return 1 if ($_->is_failed())} @{$self->get_all_Alleles()};
    return 0;
}

=head2 failed_description

  Arg [1]    : $failed_description (optional)
	           The new value to set the failed_description attribute to. Should 
	           be a reference to a list of strings, alternatively a string can
	           be passed. If multiple failed descriptions are specified, they should
	           be separated with semi-colons.  
  Example    : $failed_str = $var->failed_description();
  Description: Get/Sets the failed description for this variation. The failed
	           descriptions are lazy-loaded from the database.
  Returntype : Semi-colon separated string 
  Exceptions : Thrown on illegal argument.
  Caller     : general
  Status     : At risk

=cut

sub failed_description {
    my $self = shift;
    my $description = shift;
  
    # Update the description if necessary
    if (defined($description)) {
        
        # If the description is a string, split it by semi-colon and take the reference
        if (check_ref($description,'STRING')) {
            my @pcs = split(/;/,$description);
            $description = \@pcs;
        }
        # Throw an error if the description is not an arrayref
        assert_ref($description.'ARRAY');
        
        # Update the cached failed_description
        $self->{'failed_description'} = $description;
    }
    #�Else, fetch it from the db if it's not cached
    elsif (!defined($self->{'failed_description'})) {
        $self->{'failed_description'} = $self->get_all_failed_descriptions();
    }
    
    # Return a semi-colon separated string of descriptions
    return join(";",@{$self->{'failed_description'}});
}

=head2 get_all_failed_descriptions

  Example    :  
                if ($var->is_failed()) {
                    my $descriptions = $var->get_all_failed_descriptions();
                    print "Variation " . $var->name() . " has been flagged as failed because '";
                    print join("' and '",@{$descriptions}) . "'\n";
                }
                
  Description: Gets all failed descriptions associated with this Variation.
  Returntype : Reference to a list of strings 
  Exceptions : Thrown if an adaptor is not attached to this object.
  Caller     : general
  Status     : At risk

=cut

sub get_all_failed_descriptions {
  my $self = shift;
  
    #�If the failed descriptions haven't been cached yet, load them from db
    unless (defined($self->{'failed_description'})) {
        
        #�Check that this allele has an adaptor attached
        unless (defined($self->adaptor())) {
            throw('An adaptor must be attached to the ' . ref($self)  . ' object');
        }
    
        $self->{'failed_description'} = $self->adaptor->get_all_failed_descriptions($self);
    }
    
    return $self->{'failed_description'};
}

=head2 _add_Allele

  Arg [1]    : Bio::EnsEMBL::Variation::Allele $allele
  Example    : $v->add_Allele(Bio::EnsEMBL::Variation::Alelele->new(...));
  Description: Associates an Allele with this variation. Should only be called from within the variation module
  Returntype : none
  Exceptions : throw on incorrect argument
  Caller     : general
  Status     : At Risk

=cut

sub _add_Allele {
    my $self = shift;
    my $allele = shift;

    #�Add (or replace) the allele to the hash
    $self->add_Allele($allele);
    
    #�Add a reference to ourself to the allele object
    $allele->variation($self);
  
    #�Weaken the allele's reference back to this variation object
    $allele->_weaken();
}

=head2 add_allele

  Arg [1]    : Bio::EnsEMBL::Variation::Allele $allele (Optional)
  Example    : $v->add_allele(Bio::EnsEMBL::Variation::Allele->new(...));
  Description: Add an Allele to this variation.
  Returntype : none
  Exceptions : throw on incorrect argument
  Caller     : general
  Status     : At Risk

=cut

sub add_Allele {
    my $self = shift;
    my $allele = shift;
  
    assert_ref($allele,'Bio::EnsEMBL::Variation::Allele');
    
    #�Store the allele in our private hash using the allele_id as key. This is primarily in order to quickly update allele objects that are created later and needs to be properly linked to the variation
    $self->{'alleles'}{$allele->_hash_key()} = $allele;
    
}

=head2 name

  Arg [1]    : string $newval (optional)
               The new value to set the name attribute to
  Example    : $name = $obj->name()
  Description: Getter/Setter for the name attribute
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub name{
  my $self = shift;
  return $self->{'name'} = shift if(@_);
  return $self->{'name'};
}


=head2 get_all_Genes

  Args        : None
  Example     : $genes = $v->get_all_genes();
  Description : Retrieves all the genes where this Variation
                has a consequence.
  ReturnType  : reference to list of Bio::EnsEMBL::Gene
  Exceptions  : None
  Caller      : general
  Status      : At Risk

=cut

sub get_all_Genes{
    my $self = shift;
    my $genes;
    if (defined $self->{'adaptor'}){
	my $UPSTREAM = 5000;
	my $DOWNSTREAM = 5000;
	my $vf_adaptor = $self->adaptor()->db()->get_VariationFeatureAdaptor();
	my $vf_list = $vf_adaptor->fetch_all_by_Variation($self);
	#foreach vf, get the slice is on, us ethe USTREAM and DOWNSTREAM limits to get all the genes, and see if SNP is within the gene
	my $new_slice;
	my $gene_list;
	my $gene_hash;

	foreach my $vf (@{$vf_list}){
	    #expand the slice UPSTREAM and DOWNSTREAM
	    $new_slice = $vf->feature_Slice()->expand($UPSTREAM,$DOWNSTREAM);
	    #get the genes in the new slice
	    $gene_list = $new_slice->get_all_Genes();
	    foreach my $gene (@{$gene_list}){
		if (($vf->start >= $gene->seq_region_start - $UPSTREAM) && ($vf->start <= $gene->seq_region_end + $DOWNSTREAM) && ($vf->end <= $gene->seq_region_end + $DOWNSTREAM)){
		    #the vf is affecting the gene, add to the hash if not present already
		    if (!exists $gene_hash->{$gene->dbID}){
			$gene_hash->{$gene->dbID} = $gene;
		    }
		}
	    }
	}
	#and return all the genes
	push @{$genes}, values %{$gene_hash};
    }
    return $genes;
}




=head2 get_all_VariationFeatures

  Args        : None
  Example     : $vfs = $v->get_all_VariationFeatures();
  Description : Retrieves all VariationFeatures for this Variation
  ReturnType  : reference to list of Bio::EnsEMBL::Variation::VariationFeature
  Exceptions  : None
  Caller      : general
  Status      : At Risk

=cut

sub get_all_VariationFeatures{
  my $self = shift;
  
  if(defined $self->adaptor) {
	
	# get variation feature adaptor
	my $vf_adaptor = $self->adaptor()->db()->get_VariationFeatureAdaptor();
	
	return $vf_adaptor->fetch_all_by_Variation($self);
  }
  
  else {
	warn("No variation database attached");
	return [];
  }
}

=head2 get_VariationFeature_by_dbID

  Args        : None
  Example     : $vf = $v->get_VariationFeature_by_dbID();
  Description : Retrieves a VariationFeature for this Variation by it's internal
				database identifier
  ReturnType  : Bio::EnsEMBL::Variation::VariationFeature
  Exceptions  : None
  Caller      : general
  Status      : At Risk

=cut

sub get_VariationFeature_by_dbID{
  my $self = shift;
  my $dbID = shift;
  
  throw("No dbID defined") unless defined $dbID;
  
  if(defined $self->adaptor) {
	
	# get variation feature adaptor
	my $vf_adaptor = $self->adaptor()->db()->get_VariationFeatureAdaptor();
	
	my $vf = $vf_adaptor->fetch_by_dbID($dbID);
	
	# check defined
	if(defined($vf)) {
	  
	  # check it is the same variation ID
	  if($vf->{_variation_id} == $self->dbID) {
		return $vf;
	  }
	  
	  else {
		warn("Variation dbID for Variation Feature does not match this Variation's dbID");
		return undef;
	  }
	}
	
	else {
	  return undef;
	}
  }
  
  else {
	warn("No variation database attached");
	return undef;
  }  
}



=head2 get_all_synonyms

  Arg [1]    : (optional) string $source - the source of the synonyms to
               return.
  Example    : @dbsnp_syns = @{$v->get_all_synonyms('dbSNP')};
               @all_syns = @{$v->get_all_synonyms()};
  Description: Retrieves synonyms for this Variation. If a source argument
               is provided all synonyms from that source are returned,
               otherwise all synonyms are returned.
  Returntype : reference to list of strings
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub get_all_synonyms {
  my $self = shift;
  my $source = shift;

  if($source) {
    return $self->{'synonyms'}->{$source} || []
  }

  my @synonyms = map {@$_} values %{$self->{'synonyms'}};

  return \@synonyms;
}



=head2 get_all_synonym_sources

  Arg [1]    : none
  Example    : my @sources = @{$v->get_all_synonym_sources()};
  Description: Retrieves a list of all the sources for synonyms of this
               Variation.
  Returntype : reference to a list of strings
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub get_all_synonym_sources {
  my $self = shift;
  my @sources = keys %{$self->{'synonyms'}};
  return \@sources;
}



=head2 add_synonym

  Arg [1]    : string $source
  Arg [2]    : string $syn
  Example    : $v->add_synonym('dbSNP', 'ss55331');
  Description: Adds a synonym to this variation.
  Returntype : none
  Exceptions : throw if $source argument is not provided
               throw if $syn argument is not provided
  Caller     : general
  Status     : At Risk

=cut

sub add_synonym {
  my $self   = shift;
  my $source = shift;
  my $syn    = shift;

  throw("source argument is required") if(!$source);
  throw("syn argument is required") if(!$syn);

  $self->{'synonyms'}->{$source} ||= [];

  push @{$self->{'synonyms'}->{$source}}, $syn;

  return;
}



=head2 get_all_validation_states

  Arg [1]    : none
  Example    : my @vstates = @{$v->get_all_validation_states()};
  Description: Retrieves all validation states for this variation.  Current
               possible validation statuses are 'cluster','freq','submitter',
               'doublehit', 'hapmap'
  Returntype : reference to list of strings
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub get_all_validation_states {
    my $self = shift;
    
    return Bio::EnsEMBL::Variation::Utils::Sequence::get_all_validation_states($self->{'validation_code'});
}




=head2 add_validation_state

  Arg [1]    : string $state
  Example    : $v->add_validation_state('cluster');
  Description: Adds a validation state to this variation.
  Returntype : none
  Exceptions : warning if validation state is not a recognised type
  Caller     : general
  Status     : At Risk

=cut

sub add_validation_state {
    Bio::EnsEMBL::Variation::Utils::Sequence::add_validation_state(@_);
}



=head2 source

  Arg [1]    : string $source (optional)
               The new value to set the source attribute to
  Example    : $source = $v->source()
  Description: Getter/Setter for the source attribute
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub source{
  my $self = shift;
  return $self->{'source'} = shift if(@_);
  return $self->{'source'};
}


=head2 source_type

  Arg [1]    : string $source_type (optional)
               The new value to set the source type attribute to
  Example    : $source_type = $v->source_type()
  Description: Getter/Setter for the source type attribute
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : At risk

=cut

sub source_type{
  my $self = shift;
  return $self->{'source_type'} = shift if(@_);
  return $self->{'source_type'};
}


=head2 source_description

  Arg [1]    : string $source_description (optional)
               The new value to set the source description attribute to
  Example    : $source_description = $v->source_description()
  Description: Getter/Setter for the source description attribute
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub source_description{
  my $self = shift;
  return $self->{'source_description'} = shift if(@_);
  return $self->{'source_description'};
}



=head2 source_url

  Arg [1]    : string $source_url (optional)
               The new value to set the source URL attribute to
  Example    : $source_url = $v->source_url()
  Description: Getter/Setter for the source URL attribute
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub source_url{
  my $self = shift;
  return $self->{'source_url'} = shift if(@_);
  return $self->{'source_url'};
}

=head2 is_somatic

  Arg [1]    : boolean $is_somatic (optional)
               The new value to set the is_somatic flag to
  Example    : $is_somatic = $v->is_somatic
  Description: Getter/Setter for the is_somatic flag, which identifies this variation as either somatic or germline
  Returntype : boolean
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub is_somatic {
  my ($self, $is_somatic) = @_;
  $self->{is_somatic} = $is_somatic if defined $is_somatic;
  return $self->{is_somatic};
}

=head2 get_all_Alleles

  Arg [1]    : none
  Example    : @alleles = @{$v->get_all_Alleles()};
  Description: Retrieves all Alleles associated with this variation
  Returntype : reference to list of Bio::EnsEMBL::Variation::Allele objects
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub get_all_Alleles {
  my $self = shift;
  
  my @alleles = values(%{$self->{'alleles'}});
  return \@alleles;
}



=head2 ancestral_allele

  Arg [1]    : string $ancestral_allele (optional)
  Example    : $ancestral_allele = v->ancestral_allele();
  Description: Getter/Setter ancestral allele associated with this variation
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub ancestral_allele {
  my $self = shift;
  return $self->{'ancestral_allele'} = shift if(@_);
  return $self->{'ancestral_allele'};
}

=head2 moltype

  Arg [1]    : string $moltype (optional)
               The new value to set the moltype attribute to
  Example    : $moltype = v->moltype();
  Description: Getter/Setter moltype associated with this variation
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub moltype {
  my $self = shift;
  return $self->{'moltype'} = shift if(@_);
  return $self->{'moltype'};
}


=head2 five_prime_flanking_seq

  Arg [1]    : string $newval (optional) 
               The new value to set the five_prime_flanking_seq attribute to
  Example    : $five_prime_flanking_seq = $obj->five_prime_flanking_seq()
  Description: Getter/Setter for the five_prime_flanking_seq attribute
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub five_prime_flanking_seq{
  my $self = shift;

  #setter of the flanking sequence
  return $self->{'five_prime_flanking_seq'} = shift if(@_);
  #lazy-load the flanking sequence from the database
  if (!defined $self->{'five_prime_flanking_seq'} && $self->{'adaptor'}){
      my $variation_adaptor = $self->adaptor()->db()->get_VariationAdaptor();
      ($self->{'three_prime_flanking_seq'},$self->{'five_prime_flanking_seq'}) = @{$variation_adaptor->get_flanking_sequence($self->{'dbID'})};
  }
  return $self->{'five_prime_flanking_seq'};
}




=head2 three_prime_flanking_seq

  Arg [1]    : string $newval (optional) 
               The new value to set the three_prime_flanking_seq attribute to
  Example    : $three_prime_flanking_seq = $obj->three_prime_flanking_seq()
  Description: Getter/Setter for the three_prime_flanking_seq attribute
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub three_prime_flanking_seq{
  my $self = shift;

  #setter of the flanking sequence
  return $self->{'three_prime_flanking_seq'} = shift if(@_);
  #lazy-load the flanking sequence from the database
  if (!defined $self->{'three_prime_flanking_seq'} && $self->{'adaptor'}){
      my $variation_adaptor = $self->adaptor()->db()->get_VariationAdaptor();
      ($self->{'three_prime_flanking_seq'},$self->{'five_prime_flanking_seq'}) = @{$variation_adaptor->get_flanking_sequence($self->{'dbID'})};
  }
  return $self->{'three_prime_flanking_seq'};
}


=head2 get_all_IndividualGenotypes

  Args       : none
  Example    : $ind_genotypes = $var->get_all_IndividualGenotypes()
  Description: Getter for IndividualGenotypes for this Variation, returns empty list if 
               there are none 
  Returntype : listref of IndividualGenotypes
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub get_all_IndividualGenotypes {
    my $self = shift;
	my $individual = shift;
    if (defined ($self->{'adaptor'})){
	my $igtya = $self->{'adaptor'}->db()->get_IndividualGenotypeAdaptor();
	
	return $igtya->fetch_all_by_Variation($self, $individual);
    }
    return [];
}

=head2 get_all_PopulationGenotypes

  Args       : none
  Example    : $pop_genotypes = $var->get_all_PopulationGenotypes()
  Description: Getter for PopulationGenotypes for this Variation, returns empty list if 
               there are none. 
  Returntype : listref of PopulationGenotypes
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub get_all_PopulationGenotypes {
    my $self = shift;

    #simulate a lazy-load on demand situation, used by the Glovar team
    if (!defined($self->{'populationGenotypes'}) && defined ($self->{'adaptor'})){
	my $pgtya = $self->{'adaptor'}->db()->get_PopulationGenotypeAdaptor();
	
	return $pgtya->fetch_all_by_Variation($self);
    }
    return $self->{'populationGenotypes'};

}


=head2 add_PopulationGenotype

    Arg [1]     : Bio::EnsEMBL::Variation::PopulationGenotype
    Example     : $v->add_PopulationGenotype($pop_genotype)
    Description : Adds another PopulationGenotype to the Variation object
    Exceptions  : thrown on bad argument
    Caller      : general
    Status      : At Risk

=cut

sub add_PopulationGenotype{
    my $self = shift;

    if (@_){
	if(!ref($_[0]) || !$_[0]->isa('Bio::EnsEMBL::Variation::PopulationGenotype')) {
	    throw("Bio::EnsEMBL::Variation::PopulationGenotype argument expected");
	}
	#a variation can have multiple PopulationGenotypes
	push @{$self->{'populationGenotypes'}},shift;
    }

}


=head2 ambig_code

    Args         : None
    Example      : my $ambiguity_code = $v->ambig_code()
    Description  : Returns the ambigutiy code for the alleles in the Variation
    ReturnType   : String $ambiguity_code
    Exceptions   : none    
    Caller       : General
    Status       : At Risk

=cut 

sub ambig_code{
    my $self = shift;
	
	my $code;
	
	# first try via VF
	if(my @vfs = @{$self->get_all_VariationFeatures}) {
	  if(scalar @vfs) {
		$code = $vfs[0]->ambig_code;
	  }
	}
	
	# otherwise get it via alleles attatched to this object already
	if(!defined($code)) {
	  my $alleles = $self->get_all_Alleles(); #get all Allele objects
	  my %alleles; #to get all the different alleles in the Variation
	  map {$alleles{$_->allele}++} @{$alleles};
	  my $allele_string = join "|",keys %alleles;
	  $code = &ambiguity_code($allele_string);
	}
	
	return $code;
}

=head2 var_class

    Args         : None
    Example      : my $variation_class = $vf->var_class()
    Description  : returns the class for the variation, according to dbSNP classification
    ReturnType   : String $variation_class
    Exceptions   : none
    Caller       : General
    Status       : At Risk

=cut

sub var_class{
    my $self = shift;
    
    unless ($self->{class_display_term}) {
       
        unless ($self->{class_SO_term}) {
            # work out the term from the alleles
            
            my $alleles = $self->get_all_Alleles(); #get all Allele objects
            my %alleles; #to get all the different alleles in the Variation
            map {$alleles{$_->allele}++} @{$alleles};
            my $allele_string = join '/',keys %alleles;

            $self->{class_SO_term} = SO_variation_class($allele_string);
        }

        # convert the SO term to the ensembl display term

        $self->{class_display_term} = $self->is_somatic ? 
            $VARIATION_CLASSES{$self->{class_SO_term}}->{somatic_display_term} : 
            $VARIATION_CLASSES{$self->{class_SO_term}}->{display_term};
    }
    
    return $self->{class_display_term};
}

=head2 derived_allele_frequency

  Arg[1]     : Bio::EnsEMBL::Variation::Population  $population 
  Example    : $daf = $variation->derived_allele_frequency($population);
  Description: Gets the derived allele frequency for the population. 
               The DAF is the frequency of the reference allele that is 
               different from the allele in Chimp. If none of the alleles
               is the same as the ancestral, will return reference allele
               frequency
  Returntype : float
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub derived_allele_frequency{
  my $self = shift;
  my $population = shift;
  my $daf;

  if(!ref($population) || !$population->isa('Bio::EnsEMBL::Variation::Population')) {
      throw('Bio::EnsEMBL::Variation::Population argument expected.');
  }
  my $ancestral_allele = $self->ancestral_allele();
  if (defined $ancestral_allele){
	#get reference allele
	my $vf_adaptor = $self->adaptor->db->get_VariationFeatureAdaptor();
	my $vf = shift @{$vf_adaptor->fetch_all_by_Variation($self)};
	my $ref_freq;
	#get allele in population
	my $alleles = $self->get_all_Alleles();
	
	foreach my $allele (@{$alleles}){
	  next unless defined $allele->population;
	  
	  if (($allele->allele eq $vf->ref_allele_string) and ($allele->population->name eq $population->name)){
		$ref_freq = $allele->frequency;
	  }
	}
	
	if(defined $ref_freq) {
	  if ($ancestral_allele eq $vf->ref_allele_string){
		$daf = 1 - $ref_freq
	  }
	  elsif ($ancestral_allele ne $vf->ref_allele_string){
		$daf = $ref_freq;
	  }
	}
  }
  
  return $daf;
}

=head2 derived_allele

  Arg[1]     : Bio::EnsEMBL::Variation::Population  $population 
  Example    : $da = $variation->derived_allele($population);
  Description: Gets the derived allele for the population. 
  Returntype : float
  Exceptions : none
  Caller     : general
  Status     : At Risk

=cut

sub derived_allele {
     my $self = shift();
     my $population = shift();

     my $population_dbID = $population->dbID();
     my $ancestral_allele_str = $self->ancestral_allele();

     if (not defined($ancestral_allele_str)) {
         return;
     }

     my $alleles = $self->get_all_Alleles();

     my $derived_allele_str;

     foreach my $allele (@{$alleles}) {
         my $allele_population = $allele->population();

         if (defined($allele_population) and
             $allele_population->dbID() == $population_dbID)
         {
             my $allele_str = $allele->allele();

             if ($ancestral_allele_str ne $allele_str) {
                 if (defined($derived_allele_str)) {
                     return;
                 } else {
                     $derived_allele_str = $allele_str;
                 }
             }
         }
     }
     return $derived_allele_str;
}

sub _weaken {
    my $self = shift;
    my $allele = shift;
    
    #�Assert the allele reference
    assert_ref($allele,'Bio::EnsEMBL::Variation::Allele');
    
    #�If the allele does not exist in our allele hash, do nothing
    return unless (defined($self->{'alleles'}) && exists($self->{'alleles'}{$allele->_hash_key()}));
    
    #�Weaken the link from this variation to the allele
    weaken($self->{'alleles'}{$allele->_hash_key()});
}


=head2 get_all_VariationAnnotations

  Args       : none
  Example    : my $annotations = $var->get_all_VariationAnnotations()
  Description: Getter for VariationAnnotations for this Variation, returns empty list if 
               there are none. 
  Returntype : listref of VariationAnnotations
  Exceptions : none
  Caller     : general

=cut

sub get_all_VariationAnnotations {
    my $self = shift;

    #�Assert the adaptor reference
    assert_ref($self->adaptor(),'Bio::EnsEMBL::Variation::DBSQL::BaseAdaptor');
    
    # Get the annotations from the database
    return $self->adaptor->db->get_VariationAnnotationAdaptor()->fetch_all_by_Variation($self);

}

1;
