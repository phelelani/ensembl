use strict;

use DBI;
use File::Basename;
use IPC::Open3;

# Use exonerate (or other program) to find xref-ensembl obejct mappings


# XXX
my $queryfile = "xref_dna.fasta";
my $targetfile = "ensembl_transcripts.fasta";

run_mapping($queryfile, $targetfile, ".");
store($targetfile);

sub run_mapping {

  my ($queryfile, $targetfile, $root_dir) = @_;

  # get list of methods
  my @methods = ("ExonerateBest1"); # TODO get from Ian, maybe files as well

  # foreach method, submit the appropriate job & keep track of the job name
  my @job_names;

  foreach my $method (@methods) {

    my $obj_name = "XrefMapper::Methods::$method";
    # check that the appropriate object exists
    eval "require $obj_name";
    if($@) {

      warn("Could not find object $obj_name corresponding to mapping method $method, skipping\n$@");

    } else {

      my $obj = $obj_name->new();
      my $job_name = $obj->run($queryfile, $targetfile);
      push @job_names, $job_name;
      print "Submitted LSF job $job_name to list\n";
      sleep 1; # make sure unique names really are unique

    }

  } # foreach method

  # submit depend job to wait for all mapping jobs
  submit_depend_job($root_dir, @job_names);


} # run_exonerate


sub submit_depend_job {

  my ($root_dir, @job_names) = @_;

  # Submit a job that does nothing but wait on the main jobs to
  # finish. This job is submitted interactively so the exec does not
  # return until everything is finished.

  # build up the bsub command; first part
  my @depend_bsub = ('bsub', '-K');

  # one -wended clause for each main job
  foreach my $job (@job_names) {
    push @depend_bsub, "-wended($job)";
  }

  # rest of command
  push @depend_bsub, ('-q', 'small', '-o', "$root_dir/depend.out", '-e', "$root_dir/depend.err", '/bin/true');

  #print "depend bsub:\n" . join (" ", @depend_bsub) . "\n";

  my ($depend_wtr, $depend_rtr, $depend_etr, $depend_pid);
  $depend_pid = open3($depend_wtr, $depend_rtr, $depend_etr, @depend_bsub);
  my $depend_jobid;
  while (<$depend_rtr>) {
    if (/Job <([0-9]+)> is/) {
      $depend_jobid = $1;
      print "LSF job ID for depend job: $depend_jobid \n" ;
    }
  }
  if (!defined($depend_jobid)) {
    print STDERR "Error: could not get depend job ID\n";
  }



}

=head2 store

  Arg[1]     : The target file used in the exonerate run. Used to work out the Ensembl object type.
  Arg[2]     : 
  Example    : none
  Description: Parse exonerate output files and build files for loading into target db tables.
  Returntype : List of strings
  Exceptions : none
  Caller     : general

=cut

sub store {

  my ($target_file_name) = @_;

  my $type = get_ensembl_object_type($target_file_name);

  # get or create the appropriate analysis ID
  my $analysis_id = get_analysis_id($type);

  # TODO - get this from config
  my $dbi = DBI->connect("dbi:mysql:host=ecs1g;port=3306;database=arne_core_20_34",
			 "ensadmin",
			 "ensembl",
			 {'RaiseError' => 1}) || die "Can't connect to database";

 # get current max object_xref_id
  my $max_object_xref_id = 0;
  my $sth = $dbi->prepare("SELECT MAX(object_xref_id) FROM object_xref");
  $sth->execute();
  my $max_object_xref_id = ($sth->fetchrow_array())[0];
  if (!defined $max_object_xref_id) {
    print "Can't get highest existing object_xref_id, using 1\n)";
  } else {
    print "Maximum existing object_xref_id = $max_object_xref_id\n";
  }


  #my $ox_sth = $dbi->prepare("INSERT INTO object_xref(ensembl_id, ensembl_object_type, xref_id) VALUES(?,?,?)");

  #my $ix_sth = $dbi->prepare("INSERT INTO identity_xref VALUES(?,?,?,?,?,?,?,?,?,?,?)");

  # files to write table data to
  open (OBJECT_XREF, ">object_xref.txt");
  open (IDENTITY_XREF, ">identity_xref.txt");

  my $total_lines = 0;
  my $total_files = 0;

  my $object_xref_id = $max_object_xref_id + 1;

  # keep a (unique) list of xref IDs that need to be written out to file as well
  my %primary_xref_ids;

  foreach my $file (glob("*.map")) {

    print "Parsing results from $file \n";
    open(FILE, $file);
    $total_files++;

    while (<FILE>) {

      $total_lines++;
      chomp();
      my ($label, $query_id, $target_id, $query_start, $query_end, $target_start, $target_end, $cigar_line, $score) = split(/:/, $_);
      $cigar_line =~ s/ //;

      # TODO make sure query & target are the right way around

      print OBJECT_XREF "$object_xref_id\t$target_id\t$type\t$query_id\n";
      print IDENTITY_XREF "$object_xref_id\t$query_id\t$target_id\t$query_start\t$query_end\t$target_start\t$target_end\t$cigar_line\t$score\t\\N\t$analysis_id\n";
      # TODO - evalue?
      $object_xref_id++;

      $primary_xref_ids{$query_id} = $query_id;

      # Store in database
      # create entry in object_xref and get its object_xref_id
      #$ox_sth->execute($target_id, $type, $query_id) || warn "Error writing to object_xref table";
      #my $object_xref_id = $ox_sth->{'mysql_insertid'};

      # create entry in identity_xref
      #$ix_sth->execute($object_xref_id, $query_id, $target_id, $query_start, $query_end, $target_start, $target_end, $cigar_line, $score, undef, $analysis_id) || warn "Error writing to identity_xref table";

    }

    close(FILE);

  }

  close(IDENTITY_XREF);
  close(OBJECT_XREF);

  print "Read $total_lines lines from $total_files exonerate output files\n";

  # write relevant xrefs to file
  dump_xrefs(\%primary_xref_ids);

}


sub get_ensembl_object_type {

  my $filename = shift;
  my $type;

  if ($filename =~ /gene/i) {

    $type = "Gene";

  } elsif ($filename =~ /transcript/i) {

    $type = "Transcript";

  } elsif ($filename =~ /translation/i) {

    $type = "Translation";

  } else {

    print STDERR "Cannot deduce Ensembl object type from filename $filename";
  }

  return $type;

}


sub get_analysis_id {

  my $ensembl_type = shift;

  my %typeToLogicName = ( 'transcript' => 'XrefExonerateDNA',
			  'translation' => 'XrefExonerateProtein' );

  my $logic_name = $typeToLogicName{lc($ensembl_type)};

  # TODO - get these details from Config
  my $host = "ecs1g";
  my $port = 3306;
  my $database = "arne_core_20_34";
  my $user = "ensadmin";
  my $password = "ensembl";

  my $dbi = DBI->connect("dbi:mysql:host=$host;port=$port;database=$database",
			 "$user",
			 "$password",
			 {'RaiseError' => 1}) || die "Can't connect to database";


  my $sth = $dbi->prepare("SELECT analysis_id FROM analysis WHERE logic_name='" . $logic_name ."'");
  $sth->execute();

  my $analysis_id;

  if (my @row = $sth->fetchrow_array()) {

    $analysis_id = $row[0];
    print "Found exising analysis ID ($analysis_id) for $logic_name\n";

  } else {

    print "No analysis with logic_name $logic_name found, creating ...\n";
    $sth = $dbi->prepare("INSERT INTO analysis (logic_name, created) VALUES ('" . $logic_name. "', NOW())");
    # TODO - other fields in analysis table
    $sth->execute();
    $analysis_id = $sth->{'mysql_insertid'};
    print "Done (analysis ID=" . $analysis_id. ")\n";

  }

  return $analysis_id;

}


sub dump_xrefs {

  my $xref_ids_hashref = shift;
  my @xref_ids = keys %$xref_ids_hashref;

  open (XREF, ">xref.txt");

  # TODO - get this from config
  my $xref_dbi = DBI->connect("dbi:mysql:host=ecs1g;port=3306;database=glenn_test_xref",
			      "ensro",
			      "",
			      {'RaiseError' => 1}) || die "Can't connect to database";

  my $core_dbi = DBI->connect("dbi:mysql:host=ecs1g;port=3306;database=arne_core_20_34",
			      "ensro",
			      "",
			      {'RaiseError' => 1}) || die "Can't connect to database";

  # get current highest internal ID from xref
  my $max_xref_id = 0;
  my $core_sth = $core_dbi->prepare("SELECT MAX(xref_id) FROM xref");
  $core_sth->execute();
  my $max_xref_id = ($core_sth->fetchrow_array())[0];
  if (!defined $max_xref_id) {
    print "Can't get highest existing xref_id, using 0\n)";
  } else {
    print "Maximum existing xref_id = $max_xref_id\n";
  }
  my $core_xref_id = $max_xref_id + 1;

  # keep a unique list of source IDs to build the external_db table later
  my %source_ids;

  # execute several queries with a max of 200 entries in each IN clause - more efficient
  my $batch_size = 200;

  while(@xref_ids) {

    my @ids;
    if($#xref_ids > $batch_size) {
      @ids = splice(@xref_ids, 0, $batch_size);
    } else {
      @ids = splice(@xref_ids, 0);
    }

    my $id_str;
    if(@ids > 1)  {
      $id_str = "IN (" . join(',', @ids). ")";
    } else {
      $id_str = "= " . $ids[0];
    }


    my $sql = "SELECT * FROM xref WHERE xref_id $id_str";
    my $xref_sth = $xref_dbi->prepare($sql);
    $xref_sth->execute();

    my ($xref_id, $accession, $label, $description, $source_id, $species_id);
    $xref_sth->bind_columns(\$xref_id, \$accession, \$label, \$description, \$source_id, \$species_id);

    # note the xref_id we write to the file is NOT the one we've just read
    # from the internal xref database as the ID may already exist in the core database
    while (my @row = $xref_sth->fetchrow_array()) {
      print XREF "$core_xref_id\t$accession\t$label\t$description\n";
      $source_ids{$source_id} = $source_id;
      $core_xref_id++;
      if ($source_id == 1001) {
	print "xref $xref_id has source_id 1001\n";
      }
    }

    # Now get the dependent xrefs for each of these xrefs and write them as well
    $sql = "SELECT x.accession, x.label, x.description, x.source_id FROM dependent_xref dx, xref x WHERE x.xref_id=dx.master_xref_id AND master_xref_id $id_str";
    my $dep_sth = $xref_dbi->prepare($sql);
    $dep_sth->execute();

    $dep_sth->bind_columns(\$accession, \$label, \$description, \$source_id);
    while (my @row = $dep_sth->fetchrow_array()) {
      print XREF "$core_xref_id\t$accession\t$label\t$description\tDEPENDENT\n";
      $source_ids{$source_id} = $source_id;
      $core_xref_id++;
    }
    #print "source_ids: " . join(" ", keys(%source_ids)) . "\n";

  } # while @xref_ids

  close(XREF);

  # now write the exernal_db file - the %source_ids hash will contain the IDs of the
  # sources that need to be written as external_dbs
  open(EXTERNAL_DB, ">external_db.txt");

  # get current highest internal ID from external_db
  my $max_edb_id = 0;
  my $core_sth = $core_dbi->prepare("SELECT MAX(external_db_id) FROM external_db");
  $core_sth->execute();
  my $max_edb_id = ($core_sth->fetchrow_array())[0];
  if (!defined $max_edb_id) {
    print "Can't get highest existing external_db_id, using 0\n)";
  } else {
    print "Maximum existing external_db_id = $max_edb_id\n";
  }
  my $edb_id = $max_edb_id + 1;

  my @source_id_array = keys %source_ids;
  my $source_id_str;
  if(@source_id_array > 1)  {
    $source_id_str = "IN (" . join(',', @source_id_array). ")";
  } else {
    $source_id_str = "= " . $source_id_array[0];
  }

  my $source_sql = "SELECT name, release FROM source WHERE source_id $source_id_str";
  my $source_sth = $xref_dbi->prepare($source_sql);
  $source_sth->execute();

  my ($source_name, $release);
  $source_sth->bind_columns(\$source_name, \$release);

  while (my @row = $source_sth->fetchrow_array()) {
    print EXTERNAL_DB "$edb_id\t$source_name\t$release\tXREF\n";
    # TODO knownxref etc??
    $edb_id++;
  }

  close(EXTERNAL_DB);



}
