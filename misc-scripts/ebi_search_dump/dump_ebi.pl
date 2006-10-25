# Dump gene and xref information to an XML file for indexing by the EBI's
# search engine.
#
# To copy files to the EBI so that they can be picked up:
# scp homo_sapiens_core_41_36c.xml.gz glenn@puffin.ebi.ac.uk:xml/

use strict;
use DBI;

use Getopt::Long;
use IO::Zlib;

use Bio::EnsEMBL::DBSQL::DBAdaptor;

use HTML::Entities;

my ( $host, $user, $pass, $port, $dbpattern, $max_genes, $gzip );

GetOptions( "host=s",              \$host,
	    "user=s",              \$user,
	    "pass=s",              \$pass,
	    "port=i",              \$port,
	    "dbpattern|pattern=s", \$dbpattern,
	    "gzip!",               \$gzip,
            "max_genes=i",         \$max_genes,
	    "help" ,               \&usage
	  );

if( !$host || !$dbpattern ) {
  usage();
}

my $entry_count;

my $fh;

run();

sub run() {

  # loop over databases

  my $dsn = "DBI:mysql:host=$host";
  $dsn .= ";port=$port" if ($port);

  my $db = DBI->connect( $dsn, $user, $pass );

  my @dbnames = map {$_->[0] } @{$db->selectall_arrayref("show databases")};

  for my $dbname (@dbnames) {

    next if ($dbname !~ /$dbpattern/);

    my $file = $dbname . ".xml";
    $file .= ".gz" if ($gzip);

    if ($gzip) {

      $fh = new IO::Zlib;
      $fh->open("$file", "wb9") || die ("Can't open compressed stream to $file");

    } else  {

      open(FILE, ">$file") || die "Can't open $file";

    }

    print "Dumping $dbname to $file\n";

    my $start_time = time;

    my $dba = new Bio::EnsEMBL::DBSQL::DBAdaptor('-host' => $host,
						 '-port' => $port,
						 '-user' => $user,
						 '-pass' => $pass,
						 '-dbname' => $dbname,
						 '-species' => $dbname);

    header($dba, $dbname);

    content($dba);

    footer();

    print_time($start_time);

  }

}

# -------------------------------------------------------------------------------

sub header {

  my ($dba, $dbname) = @_;

  p ("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>");
  p ("<database>");
  p ("<name>$dbname</name>");

  my $meta_container = $dba->get_MetaContainer();
  my $species = @{$meta_container->list_value_by_key('species.common_name')}[0];

  p ("<description>Ensembl $species database</description>");

  my $release = @{$meta_container->list_value_by_key('schema_version')}[0];
  my $date = @{$meta_container->list_value_by_key('xref.timestamp')}[0]; # near enough for now
  $date = munge_release_date($date);

  p ("<release>$release</release>");
  p ("<release_date>$date</release_date>");

  p ("");
  p ("<entries>");


}

# -------------------------------------------------------------------------------

sub content {

  my ($dba) = @_;

  $entry_count = 0;

  my $gene_adaptor = $dba->get_GeneAdaptor();

  foreach my $gene (@{$gene_adaptor->fetch_all()}) {

    last if ($max_genes && $entry_count >= $max_genes);

    # general gene info
    p("");
    p ("<entry id=\"" . $gene->stable_id() . "\">");

    p ("<name>" . $gene->display_id() . "</name>");

    my $description = encode_entities($gene->description()); # do any other fields need encoding?

    p ("<description>" . $description . "</description>");

    my $created = $gene->created_date();
    my $modified = $gene->modified_date();

    if ($created || $modified) {
      p ("<dates>");
      p ("<date type=\"creation\" value=\"" . format_date($created) . "\"/>") if ($created);
      p ("<date type=\"last_modification\" value=\"" . format_date($modified) . "\"/>") if ($modified);
      p ("</dates>");
    }

    # xrefs - deal with protein_ids separately, as additional fields
    my @protein_ids;

    p ("<cross_references>");

    foreach my $xref (@{$gene->get_all_DBLinks()}) {

      if ($xref->dbname() !~ /protein_id/) {
	my $display_id = $xref->display_id();
	$display_id =~ s/<.+>//g;
	p ("<ref dbname=\"" . $xref->dbname() ."\" dbkey=\"" . $display_id. "\"/>");
      } else {
	push @protein_ids, $xref->display_id();
      }
    }

    p ("</cross_references>");

    # additional fields - transcript, translation etc
    p ("<additional_fields>");

    foreach my $transcript (@{$gene->get_all_Transcripts()}) {

      p ("<field name=\"transcript\">" . $transcript->stable_id() . "</field>");

      my $translation = $transcript->translation();
      p ("<field name=\"translation\">" . $translation->stable_id() . "</field>") if ($translation);

    }

    foreach my $protein_id (@protein_ids) {
      p ("<field name=\"protein_id\">" . $protein_id . "</field>");
    }

    p ("</additional_fields>");

    # close tag
    p ("</entry>");

    $entry_count++;

  }



}



# -------------------------------------------------------------------------------

sub footer {


  p ("</entries>");

  p ("<entry_count>$entry_count</entry_count>");

  p ("</database>");

  print "Dumped $entry_count entries\n";

  if ($gzip) {

    $fh->close();

  } else {
    close(FILE);
  }
  
}


# -------------------------------------------------------------------------------

sub p {

  my $str = shift;

  # TODO - encoding

  $str .= "\n";

  if ($gzip) {

    print $fh $str;

  } else {

    print FILE $str;

  }

}

# -------------------------------------------------------------------------------

sub format_date {

  my $t = shift;

  my ($y, $m, $d, $ss, $mm, $hh) = (localtime($t))[5,4,3,0,1,2];
  $y += 1900;
  $d = "0" . $d if ($d < 10);
  my $mm = text_month($m);

  return "$d-$mm-$y";

}

# -------------------------------------------------------------------------------

sub munge_release_date {

  my $t = shift; # e.g. 2006-09-15 02:33:45

  my ($date, $time) = split(/ /, $t);
  my ($y, $m, $d) = split(/\-/, $date);
  my $mm = text_month($m);

  return "$d-$mm-$y";

}

# -------------------------------------------------------------------------------

sub text_month {

  my $m = shift;

  my @months = qw[JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC];

  return $months[$m];

}

# -------------------------------------------------------------------------------

sub print_time {

  my $start = shift;

  my $t = time - $start;
  my $s = $t % 60;
  $t = ($t - $s) / 60;
  my $m = $t % 60;
  $t = ($t - $m) /60;
  my $h = $t % 60;

  print "Time taken: " . $h . "h " . $m . "m " .$s . "s\n";

}

# -------------------------------------------------------------------------------

sub usage {
  print <<EOF; exit(0);

Usage: perl $0 <options>

  -host       Database host to connect to.

  -port       Database port to connect to.

  -dbpattern  Database name regexp

  -user       Database username.

  -pass       Password for user.

  -gzip       Compress output as it's written.

  -max_genes  Only dump this many genes for testing.

  -help       This message.

EOF

}
