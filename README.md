# Config And Installers For Software - CAIFS

CAIFS is a tool to handle installing software across various unix-like operating systems. If you work with multiple
flavours of linux, build docker containers and work with macs, then this tool will help you consistently install
software and matching configuration across all of them.

CAIFS takes inspiration from Stow and especially Tuckr, in that it is a dotfile manager, with the ability to run
scripts. Unlike Tuckr though, CAIFS takes it a step further and allows you to define different installs for different
operating systems and even architectures. This is done via hook scripts and defining custom functions per os-flavour

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
}
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

> [!NOTE]
> This CAIFS repo itself is a valid caifs collection, containing a single target, caifs!
> See a curated library of scores of more installers at <https://github.com/vasdee/caifs-common/>

## Install and Usage

YOLO it onto your system to install locally within `~/.local/`

`curl -sL https://github.com/vasdee/caifs/install.sh | sh`

OR

Install globally by using env var `INSTALL_PREFIX=/usr/local/` and root privileges

`INSTALL_PREFIX=/usr/local/ curl -sOL https://github.com/vasdee/caifs/install.sh | sudo sh -c`

Check it's working and on your path with -

`caifs --version` or `caifs --help`

OR

Clone the repository and install CAIFS, using CAIFS

``` shell
git clone https://github.com/vasdee/caifs/caifs.git
./caifs/config/bin/caifs add caifs -d . --link-root "$HOME/.local"
```

## Collection Structure

A CAIFS collection is a directory containing targets. Each target has a `config/` directory for files to symlink and an
optional `hooks/` directory for install scripts.

```text
my-dotfiles/
├── git/
│   ├── config/
│   │   ├── .gitconfig
│   │   └── .gitconfig.d/
│   │       └── aliases.config
│   └── hooks/
│       └── pre.sh
├── bash/
│   └── config/
│       ├── .bashrc
│       └── .bashrc.d/
│           └── aliases.bash
└── nvim/
    └── config/
        └── .config/
            └── nvim/
                └── init.lua
```

**Config files** mirror their destination path relative to `$HOME` (or `$CAIFS_LINK_ROOT`):

- `git/config/.gitconfig` → `~/.gitconfig`
- `nvim/config/.config/nvim/init.lua` → `~/.config/nvim/init.lua`

Three types of hooks exist, `pre.sh`, `post.sh` and `rm.sh`. Following on from the above example, if you wanted to do a
`pre.sh` hook that installed git, before the configuration was symlinked across, then this would like like:

`git/hooks/pre.sh`

**Hook scripts** define functions named after OS identifiers. CAIFS detects the OS and calls the matching function:

``` shell
# git/hooks/pre.sh

fedora() {
    rootdo dnf install -y git-core
}

ubuntu() {
    rootdo apt-get install -y git
}

arch() {
    rootdo pacman -S --noconfirm git
}

macos() {
    brew install git
}

linux() {
    # Runs on any Linux after the distro-specific function
    echo "Git installed on Linux"
}

generic() {
    # Runs on all platforms last
    echo "Git setup complete"
}
```

Available function names:

- Distro-specific: `fedora`, `ubuntu`, `arch`, `debian`, etc. (from `/etc/os-release` ID)
- `linux` - any Linux system
- `macos` - macOS/Darwin
- `generic` - all platforms
- `container` - runs when inside a container (Docker, Podman, LXC, etc.)

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

# remove symlinks for a target
caifs rm git -d ~/my-dotfiles --links

# run remove hook script
caifs rm git -d ~/my-dotfiles --hooks
```

## Environment Variables

| Variable             | Default | Description                                                                  |
|----------------------|---------|------------------------------------------------------------------------------|
| `CAIFS_COLLECTIONS`  | `$PWD`  | Colon-separated list of collection paths to search for targets               |
| `CAIFS_LINK_ROOT`    | `$HOME` | Destination root for symlinks (e.g., set to `/` for system-wide configs)     |
| `CAIFS_VERBOSE`      | `1`     | Set to `0` to enable debug output                                            |
| `CAIFS_RUN_FORCE`    | `1`     | Set to `0` to force overwrite existing files/links                           |
| `CAIFS_RUN_LINKS`    | `0`     | Set to `1` to skip symlinking (equivalent to `--hooks`)                      |
| `CAIFS_RUN_HOOKS`    | `0`     | Set to `1` to skip hooks (equivalent to `--links`)                           |
| `CAIFS_DRY_RUN`      | `1`     | Set to `0` to show what would run without making changes                     |
| `CAIFS_IN_CONTAINER` | unset   | Set to any value to force container detection (triggers `container()` hooks) |

## Advanced Configuration

### Define multiple collections

The environment variable, `$CAIFS_COLLECTIONS`, can be set with multiple `:`-delimited directory paths. Much like the
standard `$PATH` variable. Setting this variable is the equivalent of supplying multiple `-d|--directory`
arguments to the `caifs add|rm` command itself.

Using the `-d|--directory` arguments _will_ override any `$CAIFS_COLLECTIONS` variable set, allowing you to work with a
collection in isolation.

### Install to non-$HOME area

By default, CAIFS configuration will be linked to the current `$HOME` variable. This is desirable for most use cases
where you want to manage personal dotfiles.

If you need to manage files beyond the `$HOME` area, perhaps you have some custom networking that is required to be
added underneath `/` - then CAIFS has two options.

#### Leading ^ character in config path

A config file under `<target>/config/` with a leading `^` will be interpreted as being a `/` or root level file. For
example, `my_sudo/config/^etc/sudoers.d/01-mysudo.conf` will be attempted to be linked to
`/etc/sudoers.d/01-mysudo.conf`

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

### Command Options

| Option            | Env Variable        | Description                                |
|-------------------|---------------------|--------------------------------------------|
| `--verbose`, `-v` | `CAIFS_VERBOSE=0`   | Show debug logs                            |
| `--force`, `-f`   | `CAIFS_RUN_FORCE=0` | Remove existing links/files on conflict    |
| `--links`, `-l`   | `CAIFS_RUN_LINKS=0` | Run only links, disable hooks              |
| `--hooks`, `-h`   | `CAIFS_RUN_HOOKS=0` | Run only hooks, disable links              |
| `--dry-run`, `-n` | `CAIFS_DRY_RUN=0`   | Show what would run without making changes |
