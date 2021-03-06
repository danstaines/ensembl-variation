#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk.org>.

=cut


use strict;
use DBI;
use Getopt::Long;

my $config = {};

my $table_phe_map = 'MTMP_tmp_phenotype_map';
my $table_pf_bak  = 'MTMP_tmp_phenotype_feature_bak';
my $table_phe_bak = 'MTMP_tmp_phenotype_bak';
my $table_poa_bak = 'MTMP_tmp_phenotype_ontology_accession_bak';


GetOptions(
  $config,
  'host|h=s',
  'user|u=s',
  'port|P=i',
  'password|p=s',
  'db|d=s',
  'help=s'
) or die "ERROR: Could not parse command line options\n";

if($config->{help}) {
  usage();
  exit(0);
}

$config->{port} ||= 3306;

for(qw(host user port password db)) {
  die "ERROR: --$_ not defined\n" unless defined($config->{$_});
}

my $connection_string = sprintf(
  "DBI:mysql:database=%s:host=%s;port=%s",
  $config->{db},
  $config->{host},
  $config->{port}
);

# connect to DB
my $dbc = DBI->connect(
  $connection_string,
  $config->{user},
  $config->{password},
  {'RaiseError' => 1}
);

print "Getting phenotype descriptions\n";

# get phenotype descriptions
my $sth = $dbc->prepare("SELECT phenotype_id, description FROM phenotype");
my ($id, $desc);
$sth->execute();
$sth->bind_columns(\$id, \$desc);

my %descs;
$descs{$id} = $desc while($sth->fetch());
$sth->finish();

# map a reverse of the hash
my %id_by_desc = map {$descs{$_} => $_} keys %descs;

# store a "normalised version"
my %normalised;
my %denormalised;

foreach my $string(keys %id_by_desc) {
  my $normal = lc($string);
  $normal =~ s/\W//g;
  
  $normalised{$string} = $normal;
  push @{$denormalised{$normal}}, $string;
}

# create a table to store mappings
$dbc->do(qq{
  CREATE TABLE IF NOT EXISTS `$table_phe_map` (
    `old_phenotype_id` int(11) unsigned NOT NULL,
    `new_phenotype_id` int(11) unsigned NOT NULL,
    KEY `old_phenotype_id` (`old_phenotype_id`),
    KEY `new_phenotype_id` (`new_phenotype_id`)
  )
});
# $dbc->do(qq{TRUNCATE TABLE $table_phe_map});

$sth = $dbc->prepare("INSERT INTO $table_phe_map (old_phenotype_id, new_phenotype_id) VALUES (?, ?)");

my $count = 0;

print "Finding semantic matches\n";

foreach my $normal(keys %denormalised) {
  if(scalar @{$denormalised{$normal}} > 1) {
    
    # create sort structure
    my @sort;
    
    foreach my $string(@{$denormalised{$normal}}) {
      my $c = $string =~ tr/[A-Z]/[A-Z]/;
      
      push @sort, {
        uc => $c,
        length => length($string),
        string => $string
      };
    }
    
    # sort
    @sort = map {$_->{string}} sort {$a->{uc} <=> $b->{uc} || $a->{length} <=> $b->{length}} @sort;
    my $main = shift @sort;
    
    my $new_id = $id_by_desc{$main};
    
    for(@sort) {
      $count++;
      $sth->execute($new_id, $id_by_desc{$_});
    }
  }
}

$sth->finish();

if($count) {
  my $a;
  
  print "\nFound $count semantic duplicate entries in phenotype\n";
  
  print "Backing up phenotype_feature entries to $table_pf_bak\n";

  # create backups of the entries we're going to change
  $dbc->do(qq{
    CREATE TABLE IF NOT EXISTS `$table_pf_bak`
    LIKE phenotype_feature
  });
  $a = $dbc->do(qq{
    INSERT IGNORE INTO $table_pf_bak
    SELECT pf.*
    FROM phenotype_feature pf, $table_phe_map pm
    WHERE pm.old_phenotype_id = pf.phenotype_id
  });
  print "Backed up $a entries\n";
  
  print "Backing up phenotype entries to $table_phe_bak\n";

  $dbc->do(qq{
    CREATE TABLE IF NOT EXISTS `$table_phe_bak`
    LIKE phenotype
  });
  $a = $dbc->do(qq{
    INSERT IGNORE INTO $table_phe_bak
    SELECT p.*
    FROM phenotype p, $table_phe_map pm
    WHERE pm.old_phenotype_id = p.phenotype_id
  });
  print "Backed up $a entries\n";
  
  ## back up the ontology accessions
  $dbc->do(qq{
    CREATE TABLE IF NOT EXISTS `$table_poa_bak`
    LIKE phenotype_ontology_accession
  });
  $a = $dbc->do(qq{
    INSERT IGNORE INTO $table_poa_bak
    SELECT poa.*
    FROM phenotype_ontology_accession poa, $table_phe_map pm
    WHERE pm.old_phenotype_id = poa.phenotype_id
  });
  print "Backed up $a phenotype_ontology_accession entries\n";
  


  print "Updating entries in phenotype_feature\n";

  # alter the phenotype_feature entries
  $a = $dbc->do(qq{
    UPDATE phenotype_feature pf, $table_phe_map pm
    SET pf.phenotype_id = pm.new_phenotype_id
    WHERE pf.phenotype_id = pm.old_phenotype_id
  });
  print "Updated $a phenotype_feature entries\n";
  
  print "Updating entries in phenotype_ontology_accession\n";

  # alter the phenotype_ontology_accession entries
  # some will already by assigned to the same accessions so update will fail
  $a = $dbc->do(qq{
    UPDATE IGNORE phenotype_ontology_accession poa, $table_phe_map pm
    SET poa.phenotype_id = pm.new_phenotype_id
    WHERE poa.phenotype_id = pm.old_phenotype_id
  });
  print "Updated $a phenotype_ontology_accession entries\n";

  print "Removing entries from phenotype_ontology_accession\n";

  # delete from phenotype_ontology_accession
  $a = $dbc->do(qq{
    DELETE FROM poa
    USING phenotype_ontology_accession poa, $table_phe_map pm
    WHERE poa.phenotype_id = pm.old_phenotype_id
  });


  print "Removing entries from phenotype\n";

  # delete from phenotype
  $a = $dbc->do(qq{
    DELETE FROM p
    USING phenotype p, $table_phe_map pm
    WHERE p.phenotype_id = pm.old_phenotype_id
  });

  print "Removed $a entries\n";
}

else {
  print "\n Found no duplicates, removing $table_phe_map table\n";
  $dbc->do(qq{DROP TABLE $table_phe_map});
}

print "\nAll done!\n";



sub usage {
  print qq{#---------------------------#
# rationalise_phenotypes.pl #
#---------------------------#

This script looks for semantic duplicates in the phenotype table using the
description column. Any phenotypes that match in all alphanumeric characters
(spaces and punctuation not considered) will be merged into one entry.

Removed phenotypes are backed up to $table_phe_bak
Changed phenotype_feature entries are backed up to $table_pf_bak

Usage:
perl rationalise_phenotypes.pl -h [host] -u [user] -p [pass] -P [port] -d [database]

};
}
