# Config And Installers For Software - CAIFS

CAIFS is a tool to handle installing software across various unix-like operating systems. If you work with multiple 
flavours of linux, build docker containers and work with macs, then this tool will help you consistently install 
software and matching configuration across all of them.

CAIFS takes inspiration from Stow and especially Tuckr, in that it is a dotfile manager, with the ability to run scripts. 
Unlike Tuckr though, CAIFS takes it a step further and allows you to define different installs for different operating systems
and even architectures. This is done via hook scripts and defining custom functions per os-flavour

For example, the following hook script (a `pre.sh` in this case), demonstrates how a single hook script can be defined 
to work across operating systems, in this case installing curl in three different ways.

``` shell

fedora() {
    rootdo dnf install -y curl
}

macos() {
    brew install curl
}

debian() {
    rootdo apt-get install -y curl
```

Running the hooks on your Fedora, MacOS or Debian host in this case would be performed by

`caifs add curl --hooks`

Running the equivalent in a docker file, after a bootstrap gives you consistency

``` Dockerfile
FROM debian:trixie-slim

RUN curl -sL https://github.com/vasdee/caifs/install.sh | sh && \
    caifs add curl --hooks

# Your other docker image build 
...

```

> [!IMPORTANT]
> This CAIFS repo does not container installers, this is just the shell script for managing your own set of installers
> See a curated library of scores of installers at https://github.com/vasdee/caifs-common/

## Install and Usage

YOLO it onto your system to install locally within `~/.local/`

`curl -sL https://github.com/vasdee/caifs/install.sh | sh`

OR

Install globally by using env var `INSTALL_PREFIX=/usr/local/` and root privileges

`INSTALL_PREFIX=/usr/local/ curl -sOL https://github.com/vasdee/caifs/install.sh | sudo sh -c`

Check it's working and on your path with -

`caifs --version` or `caifs --help`

## Creating a caifs collection

CAIFS expects a simple structure for it work, a containing directory, with the name of the software target, for example, 
`curl/`, `git/`, `just/` etc, and 1 or both of the subdirectories called `config` and `hooks`.

Config files should live under the target name of an application, for example for a `.gitconfig` installed as part of the
git target, you need this structure.

`git/config/.gitconfig`

Three types of hooks exist, `pre.sh`, `post.sh` and `rm.sh`. Following on from the above example, if you wanted to do a 
`pre.sh` hook that installed git, before the configuration was symlinked across, then this would like like:

`git/hooks/pre.sh`

## Usage Examples

``` shell
# does symlinking and pre/post hooks for target uv
caifs add uv

# does only symlinking for target uv
caifs add uv --links

# does only hooks for target uv
caifs add uv --hooks

# run multiple hooks for targets uv, ruff and poetry in that order
caifs add uv ruff poetry --hooks

# force an override of bash config files if the links exist already
caifs add bash --links --force

# run over multiple collections, with a first-link wins scenario
caifs add git -d ~/my-personal-collection -d ~/my-work-collection

# same as above, but using the environment variable to replace the -d|--directory option
CAIFS_COLLECTIONS="~/my-personal-collection:~/my-work-collection" \
    caifs add git
```

## Advanced CAIFS Configuration and Usage

By default, running `caifs run <target>` will run both hooks and links for the `<target>` in the current working directory,
defined by `$PWD`.

### Define multiple collections

The environment variable, `$CAIFS_COLLECTIONS`, can be set with multiple `:`-delimited directory paths. Much like the
standard `$PATH` variable. Setting this variable is the equivalent of supplying multiple `-d|--directory` 
arguments to the `caifs add|rm ` command itself. 

Using the `-d|--directory` arguments _will_ override any `$CAIFS_COLLECTIONS` variable set, allowing you to work with a 
collection in isolation.

### Install to non-$HOME area

By default, CAIFS configuration will be linked to the current `$HOME` variable. This is desirable for most use cases 
where you want to manage personal dotfiles.

If you need to manage files beyond the `$HOME` area, perhaps you have some custom networking that is required to be added 
underneath `/` - then CAIFS has two options. 

#### Leading ^ character in config path

A config file under `<target>/config/` with a leading `^` will be interpreted as being a `/` or root level file. 
For example, `my_sudo/config/^etc/sudoers.d/01-mysudo.conf` will be attempted to be linked to `/etc/sudoers.d/01-mysudo.conf`

Attempted, because CAIFS will attempt to escalate privileges

1. CAIFS is currently running as root, i.e. uid=0, run `<the command>` as is.
2. sudo is available and run `sudo <the command>`
3. fallback to `su -c <the command>` to issue the command

> [!NOTE]
> Some of these options may prompt for passwords, depending on your setup

#### Altering the CAIFS_LINK_ROOT variable

It may be useful in certain situations, particularly in docker builds which generally run as root, to set an alternative 
to the default `$HOME` destination for links. 

You can specify this with the `-r|--link-root` flags for the `add|rm` commands or use the `$CAIFS_LINK_ROOT` environment
variable

In a typical docker builds, or perhaps escalated automation scenarios where you are running as root, but want the 
configuration to be placed into another users home directory. 

``` Dockerfile
FROM debian:trixie-slim

# Add an app user with a home directory at /app
RUN useradd \
    --create-home \
    --home-dir /app \
    --uid 1000 \
    --shell /bin/sh \
    appuser


# Copy over a collection, or perhaps curl one on from github
COPY my-docker-collection /usr/local/share/my-docker-collection

# install some software and add the config from a custom collection, but 
# create the links at the link-root of /app/
RUN curl -sL https://github.com/vasdee/caifs/install.sh | sh && \
    caifs add uv git pre-commit ruff \
      --link-root /app \
      -d /usr/local/share/my-docker-collection
```

### Standard command overrides

Some general, more self-explanatory options

#### Show more debugging information

Shows debug logs and is far more verbose. Useful when things go wrong or when adding features

`--verbose|-v` or `$CAIFS_VERBOSE=0`

#### Remove any pre-existing links in the event of conflicts

Will force CAIFS to unlink existing links, or rm standard files if they exist. Should be used with caution
because you could lose your hard-earned configuration, before it is versioned!

`--force|-f` or  `$CAIFS_RUN_FORCE=0`

#### Run links only

By default, CAIFS runs both links and hooks, unless specified.

Run only the links component during an `add` or `rm` action. This effectively disables hooks

`--links|-l` or `$CAIFS_RUN_LINKS=0`

Run only the hooks component during an `add` or `rm` action. This effectively disables links

`--hooks|-h` or `$CAIFS_RUN_HOOKS=0`

The following is the equivalent of the default, which is to run both hooks and links

`caifs add curl --hooks --links` 


#### Don't do anything to the filesystem

A useful option when you want to see what would run, before you run it. This includes the removal of links, or files 
during a `--force` scenario. Also applies to hooks

`--dry-run|-n` or  `$CAIFS_DRY_RUN=0`

## Todo

* take the conventions from tuckr regarding config paths starting with a ^ - but elevate via rootdo

