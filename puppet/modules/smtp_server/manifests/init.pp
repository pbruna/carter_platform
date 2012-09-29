class smtp_server {
	$logstash_server = "localhost"
	$logstash_port = "5544"
	$mysql_auth_servers = ["localhost"]
	
	include mta_server
	include auth_sasl_server
	include logstash
	include rsyslog
	
	class rsyslog {
		
		file {"/etc/rsyslog.conf":
			ensure => file,
			owner => "root",
			group => "root",
			mode => "0644",
			content => template("smtp_server/rsyslog.conf.erb"),
			notify => Service["rsyslog"]
		}
		
		service {"rsyslog":
			ensure => running,
			enable => true,
			hasrestart => true,
			hasstatus => true,
			require => [ File["/etc/rsyslog.conf"]]
		}
		
	}
	
	class logstash {
		package {"java-1.7.0-openjdk":
			ensure => present,
		}
		
		file {"/opt/logstash":
			ensure => directory,
			require => Package["java-1.7.0-openjdk"]
		}
		
		file {"/opt/logstash/patterns":
			ensure => directory,
			owner => "root",
			group => "root",
			mode => "755",
			require => File["/opt/logstash"]
		}
		
		file {"/opt/logstash/plugins":
			ensure => directory,
			owner => "root",
			group => "root",
			mode => "755",
			require => File["/opt/logstash"]
		}
		
		file {"/opt/logstash/plugins/logstash":
			ensure => directory,
			owner => "root",
			group => "root",
			mode => "755",
			require => File["/opt/logstash/plugins"]
		}
		
		file {"/opt/logstash/plugins/logstash/outputs":
			ensure => directory,
			owner => "root",
			group => "root",
			mode => "755",
			require => File["/opt/logstash/plugins/logstash"]
		}
		
		file {"logstash-monolithic.jar":
			ensure => file,
			path => "/opt/logstash/logstash-monolithic.jar",
			mode => "644",
			source => "puppet:///modules/smtp_server/logstash-1.1.2.dev-dh.jar",
			require => File["/opt/logstash"]
		}
		
		file {"/etc/logstash.conf":
			ensure => file,
			owner => "root",
			mode => "0644",
			source => "puppet:///modules/smtp_server/logstash.conf",
			require => File["logstash-monolithic.jar"],
			notify => Service["logstash"]
		}
		
		# TODO: Arreglar PID para status
		file {"logstash_init":
			ensure => file,
			owner => root,
			mode => "755",
			path => "/etc/init.d/logstash",
			source => "puppet:///modules/smtp_server/logstash.sh",
			require => File["logstash-monolithic.jar"]
		}
		
		service {"logstash":
			ensure => running,
			enable => true,
			hasstatus => true,
			hasrestart => true,
			require => [File["logstash_init"], File["/etc/logstash.conf"]]
		}
		
		file {"logstash_patterns":
			ensure => file,
			owner => "root",
			mode => "0644",
			path => "/opt/logstash/patterns/grok-patterns",
			source => "puppet:///modules/smtp_server/grok-patterns",
			notify => Service["logstash"]
		}
		
	}
	
	class mta_server {
		package {"postfix":
			ensure => present
		}
	
		file {"postfix_main":
			ensure => file,
			owner => "root",
			group => "root",
			path => "/etc/postfix/main.cf",
			require => Package["postfix"],
			notify => Service["postfix"],
			content => template("smtp_server/main.cf.erb")
		}
		
		file {"postfix_master":
			ensure => present,
			owner => "root",
			group => "root",
			path => "/etc/postfix/master.cf",
			require => Package["postfix"],
			notify => Service["postfix"],
			source => "puppet:///modules/smtp_server/master.cf"
		}
	
		service {"postfix":
			ensure => running,
			enable => true,
			hasstatus => true,
			hasrestart => true,
			require => [Package["postfix"], File["postfix_main"]]
		}
	}
	
	class auth_sasl_server {
		package {"dovecot":
			ensure => present
		}
		
		package {"dovecot-mysql":
			ensure => present
		}
		
		file {"dovecot_conf": 
			ensure => present,
			owner => "root",
			group => "root",
			mode => "644",
			path => "/etc/dovecot/dovecot.conf",
			source => "puppet:///modules/smtp_server/dovecot.conf",
			require => Package["dovecot"],
			notify => Service["dovecot"]
		}
		
		file {"dovecot_logrotate":
			ensure => file,
			owner => "root",
			group => "root",
			mode => "644",
			path => "/etc/logrotate.d/dovecot",
			source => "puppet:///modules/smtp_server/dovecot_logrotate",
			require => Package["dovecot"],
		}
		
		file {"dovecot_sql":
			ensure => present,
			owner => "root",
			group => "root",
			mode => "644",
			path => "/etc/dovecot/dovecot-sql.conf",
			content => template("smtp_server/dovecot-sql.conf.erb"),
			require => [Package["dovecot"], File["dovecot_conf"]],
			notify => Service["dovecot"]
		}
		
		service {"dovecot":
			ensure => running,
			enable => true,
			hasrestart => true,
			hasstatus => true,
			require => [Package["dovecot"], File["dovecot_conf", "dovecot_sql"]]
		}
		
	}
	
}