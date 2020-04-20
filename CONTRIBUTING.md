# Contributing to the Repository

## Organization

Please reference the [README.md][readme-uri] for the file layout of this repository.

## Getting Started

### Setup the Environment

In order to make a contribution the [GitLab repository][contribute-url] **MUST** be [forked][fork-url] into a personal
or team namespace. Branch policies are in place to restrict the creation of additional branches on the primary
repository. Once the contribution is complete, submit a merge request back to the upstream repo. General guidance for
forking is as follows:

1. [Create the fork][fork-url]
2. Clone the fork locally
3. add the  as the upstream:

```sh
# if using HTTPS (recommended)
git remote add upstream https://gitlab.com/deavon-and-tiffany/kubernetes/deployments
#
# OR
#
# if using SSH
git remote add upstream git@gitlab.com:deavon-and-tiffany/kubernetes/deployments.git
```

4. synchronize the fork and upstream:

```sh
git checkout master
git pull --all
git merge --ff-only upstream/master
git push
```

5. create a new working feature branch

```sh
git checkout --branch some-new-feature
```

6. make the contribution
7. push the contribution to the origin (fork)

```sh
git commit --all --edit
```

8. open the merge request
9. Repeat from step 4 as necessary :)

## Commit Message Guidelines

This repository relies on automatic semantic versioning and [CHANGELOG.md][changelog-uri] generation based on
[conventional commits][conventional-commits-url]. For our use case, the following format **MUST** be used:

```text
<TYPE>(<SCOPE>): imperative subject in present tense less than 80 characters

NOTES:

Add any additional notes in imperative present tense.

BREAKING CHANGE:

Describe the previous behavior in contrast to the new behavior and how it might effect consumers.
```

Allows types are:

* **feat**: represents a new feature
* **fix**: represents a bug fix
* **build**: changes to the build definitions
* **refactor**: refactor code without expecting any behavioral change
* **test**: updates to test code only
* **perf**: updates for performance only
* **docs**: update to documentation only
* **style**: changes to style only (reformatting, whitespace changes, etc)

The `(<SCOPE>)` argument should only be included if the change is isolated to a single namespace. This should be the
name of the namespace that was modified.

Only include a BREAKING CHANGE footer if necessary. Only include a NOTES body if it adds appropriate value.

The header line **SHOULD** be in all lowercase characters and exclude any special characters other than the semi-colon
and the parentheses around the scope (if included).

Example commit message:

```text
feat(mesh-system): configure pod security policies for istio sds

* add istio-restricted psp that enables `NET_ADMIN` capability and access to the SDS host path in read-only
* add istio-privileged psp that enables `NET_ADMIN` capability and access to the SDS host path in read-only that is
  otherwise less restrictive except for access to the host
* add istio-agent psp that enables the node agent service account to write to the SDS host path
* add istio:restricted:psp cluster role intended to be used by any service account used by a pod with the sidecar
* add istio:privileged:psp role and role binding used by istio services (other than the node agent)
* add istio:agent:psp role and role binding used by the istio node agent

NOTE:

All of the resources indicated above exist in the `mesh-system` namespace except for the istio:restricted:psp cluster
role, which is (obviously), cluster wide.

This is intended to isolate the Security Discovery Service (SDS) host path used to distribute the certificate required
by the istio sidecar. Only the service account associated with the node agent has a pod security policy that allows
write access to this path.

BREAKING CHANGE:

Due to the introduction of a new pod security policy required to allow access to the SDS unix socket mapped to a host
path, any pod currently using an istio sidecar should use a service account that is bound to the `istio:restricted:psp`
cluster role. Alternatively, the account must be allowed to use a pod security policy with the following:

spec:
  # used by istio citadel to distribute sidecar certificates
  allowedHostPaths:
    - pathPrefix: "/var/run/sds"
      readOnly: true

  # required by the istio sidecar injector
  allowedCapabilities:
    - NET_ADMIN
```

> NOTE:
>
> This commit message format is ONLY required when completing the pull/merge request. We recommend rebasing and/or
> squashing any locally created commits during this process to keep the history of the master branch on the upstream
> consistent and linear.

## Bonus Content

To simplify the process of working with forks, the following aliases may be useful:

```gitconfig
[alias]
    co = checkout
    ec = config --global --edit
    up = !git pull --rebase --prune $@ && git submodule update --init --recursive
    cob = checkout -b
    fob = "!f() { git cob $1 && git push --set-upstream origin $1; }; f"
    cm = !git add . && git commit -e
    save = !git add . && git commit -m 'CHECKPOINT'
    wip = !git add -u && git commit -m 'WIP'
    mark = commit --allow-empty -m 'MARK'
    undo = reset HEAD~1 --mixed
    amend = commit -a --amend
    wipe = !git add . && git commit -qm 'WIPE CHECKPOINT' && git reset HEAD~1 --hard
    prepare = "!f() { git pull && git add . && git clean -xdf }; f"
    publish = !git ready && git flow publish
    ready = !git prepare && git commit -e
    rprune = "!f() { git remote prune ${1-origin}; }; f"
    gone = "!f() { git fetch -p; git branch -vv | grep gone] | cut -d ' ' -f 3 | xargs git branch -D 2>/dev/null; }; f"
    merged = "!f() { git branch --merged ${1-develop} | grep -v "" ${1-develop}"" | grep -v "" ${2-master}"" | xargs git branch -d 2>/dev/null; }; f"
    done = "!f() { git checkout ${1-develop} && git up && git merged ${1-develop} && git gone && git rprune ${2-origin}; }; f"
    fdone = "!f() { git done ${1-master} && git rprune ${2-upstream} && git pull --all && git merge --ff-only ${2-upstream}/${1-master} && git push; }; f"
    fclone = "!f() { local UPSTREAM_URI=$1; local ALIAS=${UPSTREAM_URI##*/}; ALIAS=${2:-${ALIAS%.*}}; local UPSTREAM=${3:-"deavon-and-tiffany"}; local ORIGIN=$(echo $ORIGIN_URI | rev | cut -d '/' -f 2 | rev); git clone ${1} ${ALIAS}; cd ${ALIAS}; UPSTREAM_URI=${UPSTREAM_URI/$ORIGIN/$UPSTREAM}; git remote add upstream ${UPSTREAM_URI} && git fdone; }; f"
    frebase = "!f() { local BRANCH=$(git rev-parse --abbrev-ref HEAD); git fdone ${1-master}; git checkout $BRANCH; git rebase -i ${1-master}; }; f"
```

There is a LOT going on here, but the stuff to care about is:

```sh
# create a fork from gitlab with the correct upstream
git fclone https://gitlab.com/MY-WORKSPACE/deployments.git

# create a new working branch
git fob my-new-feature

# commit the changes
git cm && git push

# reset for a new feature (including pruning any feature branch on the origin that has been merged to the upstream)
git fdone
```

Copyright (c) 2019. Deavon McCaffery and Tiffany Wang
See [LICENSE][license-url] for details.

[readme-uri]: README.md
[changelog-uri]: CHANGELOG.md

[contribute-url]: https://gitlab.com/deavon-and-tiffany/kubernetes/deployments
[fork-url]: https://gitlab.com/deavon-and-tiffany/kubernetes/deployments/forks/new

[conventional-commits-url]: https://www.conventionalcommits.org
