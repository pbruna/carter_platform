class catcher {
	include logstash
	
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
			source => "puppet:///modules/catcher/logstash-1.1.2.dev-dh.jar",
			require => File["/opt/logstash"]
		}
		
		file {"/etc/logstash.conf":
			ensure => file,
			owner => "root",
			mode => "0644",
			source => "puppet:///modules/catcher/logstash.conf",
			require => File["logstash-monolithic.jar"],
			notify => Service["logstash"]
		}
		
		# TODO: Arreglar PID para status
		file {"logstash_init":
			ensure => file,
			owner => root,
			mode => "755",
			path => "/etc/init.d/logstash",
			source => "puppet:///modules/catcher/logstash.sh",
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
			source => "puppet:///modules/catcher/grok-patterns",
			notify => Service["logstash"]
		}
		
	}
	
}