# PRIVATE CLASS: do not call directly
class postgresql::server::initdb {
  $needs_initdb   = $postgresql::server::needs_initdb
  $initdb_path    = $postgresql::server::initdb_path
  $datadir        = $postgresql::server::datadir
  $xlogdir        = $postgresql::server::xlogdir
  $logdir         = $postgresql::server::logdir
  $encoding       = $postgresql::server::encoding
  $locale         = $postgresql::server::locale
  $data_checksums = $postgresql::server::data_checksums
  $group          = $postgresql::server::group
  $user           = $postgresql::server::user
  $psql_path      = $postgresql::server::psql_path
  $port           = $postgresql::server::port
  $module_workdir = $postgresql::server::module_workdir
  $version        = $postgresql::params::version

  # Set the defaults for the postgresql_psql resource
  Postgresql_psql {
    psql_user  => $user,
    psql_group => $group,
    psql_path  => $psql_path,
    port       => $port,
    cwd        => $module_workdir,
  }

  if $::osfamily == 'RedHat' and $::selinux == true {
    $seltype = 'postgresql_db_t'
    $logdir_type = 'postgresql_log_t'
  }
  else {
    $seltype = undef
    $logdir_type = undef
  }

  # Make sure the data directory exists, and has the correct permissions.
  file { $datadir:
    ensure  => directory,
    owner   => $user,
    group   => $group,
    mode    => '0700',
    seltype => $seltype,
  }

  if($xlogdir) {
    # Make sure the xlog directory exists, and has the correct permissions.
    file { $xlogdir:
      ensure  => directory,
      owner   => $user,
      group   => $group,
      mode    => '0700',
      seltype => $seltype,
    }
  }

  if($logdir) {
    # Make sure the log directory exists, and has the correct permissions.
    file { $logdir:
      ensure  => directory,
      owner   => $user,
      group   => $group,
      seltype => $logdir_type,
    }
  }

  if($needs_initdb) {
    # Build up the initdb command.
    #
    # We optionally add the locale switch if specified. Older versions of the
    # initdb command don't accept this switch. So if the user didn't pass the
    # parameter, lets not pass the switch at all.
    $ic_base = "--pgdata '${datadir}'"

    $ic_encoding = $encoding ? {
      undef   => '',
      default => "--encoding '${encoding}'"
    }

    # The xlogdir need to be present before initdb runs.
    # If xlogdir is default it's created by package installer
    if($xlogdir) {
      $ic_xlog = "--xlogdir '${xlogdir}'"
      $require_before_initdb = [$datadir, $xlogdir]
    } else {
      $ic_xlog = ''
      $require_before_initdb = [$datadir]
    }

    $ic_locale = $locale ? {
      undef   => '',
      default => "--locale '${locale}'"
    }

    $ic_checksums = $data_checksums ? {
      undef   => '',
      false   => '',
      default => '--data-checksums'
    }

    $initdb_command = "${initdb_path} ${ic_base} ${ic_encoding} ${ic_xlog} ${ic_locale} ${ic_checksums}"

    # The package will take care of this for us the first time, but if we
    # ever need to init a new db we need to copy these files explicitly
    if $::osfamily == 'Debian' {
      $pcc = '/usr/bin/pg_createcluster'
      $cluster = split($datadir, '/')[-1]
      $pg_createcluster_options = "-u ${user} -g ${group} -p ${port} ${ic_encoding} -d ${datadir} ${version} ${cluster}"
      $initdb_options = "${ic_xlog} ${ic_locale} ${ic_checksums}"
      $init_command = "${pcc} ${pg_createcluster_options} -- ${initdb_options}"

      # In Debian based distrobutions we have access to pg_createcluster and
      # should use that over plain initdb so that other pg_*cluster tools work.
      exec { 'postgresql_initdb':
        command   => $init_command,
        creates   => "${datadir}/PG_VERSION",
        logoutput => on_failure,
        require   => File[$require_before_initdb],
        cwd       => $module_workdir,
      }

      if $::operatingsystemrelease =~ /^6/ or $::operatingsystemrelease =~ /^7/ or $::operatingsystemrelease =~ /^10\.04/ or $::operatingsystemrelease =~ /^12\.04/ {
        file { 'server.crt':
          ensure  => file,
          path    => "${datadir}/server.crt",
          source  => 'file:///etc/ssl/certs/ssl-cert-snakeoil.pem',
          owner   => $::postgresql::server::user,
          group   => $::postgresql::server::group,
          mode    => '0644',
          require => Exec['postgresql_initdb'],
        }
        file { 'server.key':
          ensure  => file,
          path    => "${datadir}/server.key",
          source  => 'file:///etc/ssl/private/ssl-cert-snakeoil.key',
          owner   => $::postgresql::server::user,
          group   => $::postgresql::server::group,
          mode    => '0600',
          require => Exec['postgresql_initdb'],
        }
      }
    }
    else {
      # This runs the initdb command, we use the existance of the PG_VERSION
      # file to ensure we don't keep running this command.
      exec { 'postgresql_initdb':
        command   => $initdb_command,
        creates   => "${datadir}/PG_VERSION",
        user      => $user,
        group     => $group,
        logoutput => on_failure,
        require   => File[$require_before_initdb],
        cwd       => $module_workdir,
      }
    }
  } elsif $encoding != undef {
    # [workaround]
    # by default pg_createcluster encoding derived from locale
    # but it do does not work by installing postgresql via puppet because puppet
    # always override LANG to 'C'
    postgresql_psql { "Set template1 encoding to ${encoding}":
      command => "UPDATE pg_database
        SET datistemplate = FALSE
        WHERE datname = 'template1'
        ;
        UPDATE pg_database
        SET encoding = pg_char_to_encoding('${encoding}'), datistemplate = TRUE
        WHERE datname = 'template1'",
      unless  => "SELECT datname FROM pg_database WHERE
        datname = 'template1' AND encoding = pg_char_to_encoding('${encoding}')",
    }
  }
}
