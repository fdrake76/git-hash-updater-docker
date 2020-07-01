# Git Hash Updater

This is a simple container I built to serve my own personal needs, but you may find it useful for your own as well.

## The Problem
I maintain a few containers which build third party applications from scratch.  The configurations of these applications are being perpetually updated (almost daily), so I would like to keep pace with their bleeding edge commits automatically.  Because my container Dockerfiles pull their code via git and build it as part of the container creation, docker assumes that nothing has changed and uses the cached container layer, despite the fact that the remote git repository has definitely been updated.

To resolve this, this container checks the remote git repositories each hour, and when it detects a new latest commit, will update a specified Dockerfile:

`ARG latest_commit=<hash>`

This will flag the auto-builder on Docker Hub to rebuild the image at the point where this argument has changed.

## Environment Variables
The following environment variables are used when running the container, and will error if they are not set:

* `GIT_USER_EMAIL` - The email address of the committer for your git changes.
* `GIT_USER_NAME` - The username of the committer for your git changes.

## Data Directory Setup
The data directory that is mounted as a volume should contain the following to be provided by you:

* A file called `ssh_key`, which is the private key to your git repository.  The corresponding public key should be configured in Github/Bitbucket/etc.  This is used when pushing your Dockerfile change.  The container will stop with failure if this file does not exist.
* A file called `config.json` which contains the JSON object of the repositories you want to scan and the repository and file that you want to modify.  See below for details on config examples.  If this is not created, a new one will be created with a blank array.

Additionally, repository pulls will be stored in this directory, so it should be mounted read/write.

## Config File Example
```
[
  {
    "input": {
      "repo_url": "https://github.com/InputRepo/InputRepo.git",
      "branch": "master"
  }, "output": {
      "repo_url": "git@github.com:username/RepoImWritingTo.git",
      "branch": "master",
      "docker_file": "Dockerfile"
  }
]
```

The above is a full example.  In each of the `input` and `output` blocks, only `repo_url` is required.  If `branch` is omitted, it will default to `master`, and if the `output` `docker_file` is missing, it will default to `Dockerfile`.

## Docker Compose Example
```
version: "2"

services:
  git-hash-updater:
    image: fdrake/git-hash-updater
    restart: always
    environment:
      GIT_USER_EMAIL: my@email.com
      GIT_USER_NAME: myusername
    volumes:
      - /home/myuser/git-hash-updater-data:/data
```
