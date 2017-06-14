#!/bin/sh
set -e
#
# This script is meant for quick & easy install via:
#   'curl -sSL http://get-core.novalabs.io/ | sh'
# or:
#   'wget -qO- http://get-core.novalabs.io/ | sh'
#

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

# Check if this is a forked Linux distro
check_forked() {

	# Check for lsb_release command existence, it usually exists in forked distros
	if command_exists lsb_release; then
		# Check if the `-u` option is supported
		set +e
		lsb_release -a -u > /dev/null 2>&1
		lsb_release_exit_code=$?
		set -e

		# Check if the command has exited successfully, it means we're in a forked distro
		if [ "$lsb_release_exit_code" = "0" ]; then
			# Print info about current distro
			cat <<-EOF
			You're using '$lsb_dist' version '$dist_version'.
			EOF

			# Get the upstream release info
			lsb_dist=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'id' | cut -d ':' -f 2 | tr -d '[[:space:]]')
			dist_version=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'codename' | cut -d ':' -f 2 | tr -d '[[:space:]]')

			# Print info about upstream distro
			cat <<-EOF
			Upstream release is '$lsb_dist' version '$dist_version'.
			EOF
		else
			if [ -r /etc/debian_version ] && [ "$lsb_dist" != "ubuntu" ]; then
				# We're Debian and don't even know it!
				lsb_dist=debian
				dist_version="$(cat /etc/debian_version | sed 's/\/.*//' | sed 's/\..*//')"
				case "$dist_version" in
					8|'Kali Linux 2')
						dist_version="jessie"
					;;
					7)
						dist_version="wheezy"
					;;
				esac
			fi
		fi
	fi
}

do_install() {
	# Check for previous installations
	if [ -d "./core" ]; then
		cat >&2 <<-'EOF'
			Error: a previous installation of the Nova Core SDK has been detected.
			Run this install script from another directory or remove the old installation.
		EOF
		exit 1
	fi

	# Gain root permissions
	user="$(id -un 2>/dev/null || true)"

	sh_c='sh -c'
	rootsh_c='sh -c'
	if [ "$user" != 'root' ]; then
		if command_exists sudo; then
			rootsh_c='sudo -E sh -c'
		elif command_exists su; then
			rootsh_c='su -c'
		else
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
			exit 1
		fi
	fi

	# perform some very rudimentary platform detection
	lsb_dist=''
	dist_version=''
	if command_exists lsb_release; then
		lsb_dist="$(lsb_release -si)"
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/lsb-release ]; then
		lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/debian_version ]; then
		lsb_dist='debian'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/fedora-release ]; then
		lsb_dist='fedora'
	fi
	if [ -z "$lsb_dist" ]; then
		if [ -r /etc/centos-release ] || [ -r /etc/redhat-release ]; then
			lsb_dist='centos'
		fi
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi

	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

	case "$lsb_dist" in

		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
		;;

		debian)
			dist_version="$(cat /etc/debian_version | sed 's/\/.*//' | sed 's/\..*//')"
			case "$dist_version" in
				8)
					dist_version="jessie"
				;;
				7)
					dist_version="wheezy"
				;;
			esac
		;;

		fedora|centos)
			dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
		;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;


	esac

	# Check if this is a forked Linux distro
	check_forked

	# Run setup for each distro accordingly
	case "$lsb_dist" in
		'opensuse project'|opensuse|'suse linux'|sle[sd])
			(
				set -x
				$rootsh_c 'zypper -n install bzip2 cmake git openocd python3-pip wget'
			)
			;;

		ubuntu|debian)
			export DEBIAN_FRONTEND=noninteractive
				(
					set -x
					$rootsh_c 'dpkg --add-architecture i386'
					$rootsh_c 'sleep 1; apt-get update'
					$rootsh_c 'apt-get install -y -q bzip2 cmake git libc6:i386 libncurses5:i386 openocd python3-dev python3-pip wget'
				)
			;;

		fedora|centos)
			if [ "$lsb_dist" = "fedora" ] && [ "$dist_version" -ge "22" ]; then
				(
					set -x
					$rootsh_c 'sleep 1; dnf -y -q install bzip2 cmake git openocd python3-dev python3-pip wget'
				)
			else
				(
					set -x
					$rootsh_c 'sleep 1; yum -y -q install bzip2 cmake git openocd python3-dev python3-pip wget'
				)
			fi
			;;

		*)
			# intentionally mixed spaces and tabs here -- tabs are stripped by "<<-'EOF'", spaces are kept in the output
			cat >&2 <<-'EOF'

			  Either your platform is not easily detectable, is not supported by this
			  installer script.
			EOF
			;;
	esac

	# Look for python3
	python_c='python3 '
	pip_c='pip3 '

	set -x
	$pip_c install GitPython tabulate argcomplete colorama jsonschema intelhex

	(
		set -x
		$sh_c 'mkdir -p ./core'
		$sh_c 'wget -P ./core https://launchpad.net/gcc-arm-embedded/4.9/4.9-2014-q4-major/+download/gcc-arm-none-eabi-4_9-2014q4-20141203-linux.tar.bz2 && tar xf ./core/gcc-arm-none-eabi-4_9-2014q4-20141203-linux.tar.bz2 -C ./core && mv ./core/gcc-arm-none-eabi-4_9-2014q4 ./core/gcc-arm-none-eabi && rm ./core/gcc-arm-none-eabi-4_9-2014q4-20141203-linux.tar.bz2'
		$sh_c 'git clone https://github.com/novalabs/core-tools.git ./core/core-tools'
		$python_c './core/core-tools/CoreBootstrap.py'
	)

	if command_exists activate-global-python-argcomplete3; then
		set -x
		$rootsh_c 'activate-global-python-argcomplete3'
	elif command_exists activate-global-python-argcomplete; then
		set -x
		$rootsh_c 'activate-global-python-argcomplete'
	fi

	exit 0
}

# wrapped up in a function to avoid execution of partially downloaded scripts	
do_install
