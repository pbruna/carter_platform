class carter_app {
	include rvm_setup
	include nginx
	
	user {'carter':
		ensure => present,
		home => '/home/carter',
		uid => '10001',
		managehome => true,
		shell => '/bin/bash',
	}

	file {'/home/carter/':
		ensure => directory,
		mode => "0755",
		require => User["carter"]
	}

	file {'/home/carter/App':
		ensure => directory,
		owner => 'carter',
		mode => '0644',
		require => User['carter'],
	}

	package {'sqlite-devel':
		ensure => present,
	}
	
	package {'libyaml-devel':
		ensure => present,
	}
	
	class nginx {
		file {"nginx_repo":
			ensure => present,
			owner => "root",
			mode => "0644",
			path => "/etc/yum.repos.d/nginx.repo",
			source => "puppet:///modules/carter_app/nginx.repo"
		}

		package {'nginx':
			ensure => present,
			require => File['nginx_repo']
		}
		
		file {'nginx.conf':
			ensure => present,
			owner => "root",
			mode => "0644",
			path => "/etc/nginx/nginx.conf",
			source => "puppet:///modules/carter_app/nginx.conf",
			require => Package["nginx"],
			notify => Service["nginx"]
		}
		
		service {'nginx':
			ensure => running,
			enable => true,
			hasstatus => true,
			require => Package["nginx"]
		}
	}
}

class rvm_setup {
	
	# This is necesary to download rvm
	file {'/root/.curlrc':
		ensure => file,
		owner => "root",
		content => "insecure"
	}
	
	include rvm
	if $rvm_installed == "true" {
		rvm::system_user { carter: ; }
	
		rvm_system_ruby {
		  'ruby-1.9.3-p0':
		    ensure => 'present',
			require => [File["/root/.curlrc"], User["carter"]],
		    default_use => false;
		}
	
		rvm_gemset {
		  "ruby-1.9.3-p0@rails-3.2":
		    ensure => present,
		    require => Rvm_system_ruby['ruby-1.9.3-p0'];
		}
	
		rvm_gem {
		  'ruby-1.9.3-p0@rails-3.2/bundler':
		    require => Rvm_gemset['ruby-1.9.3-p0@rails-3.2'];
		}
		
		rvm_gem {
		  'ruby-1.9.3-p0@rails-3.2/rails':
		    require => [Rvm_gemset['ruby-1.9.3-p0@rails-3.2'], Rvm_gem['ruby-1.9.3-p0@rails-3.2/bundler']];
		}
	}
	
}