# Config And Installers For Software - CAIFS

CAIFS is a tool to handle installing software across various unix-like operating systems. If you work with multiple 
flavours of linux and even macs, then this tool will help you consistently install software and matching configuration
across all of them.

CAIFS takes inspiration from Stow and especially Tuckr, in that it is a dotfile manager, with the ability to run scripts. 
Unlike Tuckr though, CAIFS takes it a step further and allows you to define different installs for different operating systems
and even architectures. This is done via hook scripts and defining custom functions per os-flavour

For example, the following hook script demonstrates how a single hook script can be defined to work across operating systems,
in this case installing git in two different ways.

``` shell

fedora() {
    rootdo dnf install -y git-core
}

macos() {
    brew install git
}

```

> [!IMPORTANT]
> This CAIFS repo does not container installers, this is just the shell script for managing your own set of installers

## Install and Usage

YOLO it onto your system to install locally within `~/.local/`

`curl -sL https://github.com/vasdee/caifs/install.sh | sh`

OR

Install globally by using env var `INSTALL_PREFIX=/usr/local/` and root privileges

`INSTALL_PREFIX=/usr/local/ curl -sOL https://github.com/vasdee/caifs/install.sh | sudo sh -c`

Check it's working and on your path with -

`caifs --version` or `caifs --help`

## Adding configuration to a caifs collection

CAIFS expects a simple structure for it work

Config files should live under the target name of an application, for example for a `.gitconfig` installed as part of the
git target, you need this structure.

`git/config/.gitconfig`

Three types of hooks exist, `pre.sh`, `post.sh` and `rm.sh`. Following on from the above example, if you wanted to do a 
pre.sh hook that installed git, before the configuration was symlinked across, then this would like like:

`git/hooks/pre.sh`

## Config and Hooks

`<target>/config/replica/path/on/filesystem/to/some/config.txt`


## Usage 

``` shell
# does symlinking and pre/post hooks for target uv
caifs run uv

# does only symlinking for target uv
caifs run uv --links

# does only hooks for target uv
caifs run uv --hooks

# run multiple hooks for targets uv, ruff and poetry in that order
caifs run uv ruff poetry --hooks

# force an override of bash config files if the links exist already
caifs run bash --links --force
```

## Environment variables

CAIFS_COLLECTIONS
CAIFS_LINK_ROOT
CAIFS_DIR
CAIFS_VERBOSE
CAIFS_RUN_FORCE
CAIFS_RUN_LINKS
CAIFS_RUN_HOOKS

## Todo

* Figure out a nice way to install software in docker, but have it accessible to a non-root user
* take the conventions from tuckr regarding config paths starting with a ^ - but elevate via rootdo
* switch tests to shunit2
* add the root escalation for ^ paths
* add the environment variable based linking

