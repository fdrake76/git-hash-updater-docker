#!/bin/bash

logthis() {
    echo "$(date): $@"
}

trap 'logthis "Stopping." && exit 0' SIGTERM

if [ -z $GIT_USER_EMAIL ]; then
	logthis "GIT_USER_EMAIL environment variable is not defined!"
	exit 1
fi
if [ -z $GIT_USER_NAME ]; then
	logthis "GIT_USER_NAME environment variable is not defined!"
	exit 1
fi

if [ ! -f /data/ssh_key ]; then
	logthis "No SSH key is defined.  Please set a private key in /data/ssh_key and configure your public key with your upstream git repository."
	exit 1
fi

if [ ! -d /data/repos ]; then
	mkdir -p /data/repos
fi

if [ ! -f /data/config.json ]; then
	logthis "/data/config.json doesn't exist.  Creating empty one."
	echo "[]" > /data/config.json
fi

SLEEP_SECONDS=3600
export GIT_SSH_COMMAND="ssh -i /data/ssh_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
git config --global user.email "$GIT_USER_EMAIL"
git config --global user.name "$GIT_USER_NAME"
declare -A REPO_HASHES
REPO_PATTERN='.*?/(.*?).git$'
for row in $(jq -c '.[]' /data/config.json); do
	REPO_URL=`echo $row | jq -r '.input.repo_url'`
	BRANCH=`echo $row | jq -r '.input.branch'`

	[[ $REPO_URL =~ $REPO_PATTERN ]]
	REPO_DIR=${BASH_REMATCH[1]}

	cd /data/repos
	if [ ! -d /data/repos/$REPO_DIR/.git ]; then
		logthis "Cloning project from $REPO_URL"
		git clone $REPO_URL
	fi

	if [ -z $BRANCH ] || [ $BRANCH == 'null' ]; then
		BRANCH='master'
	fi

	cd /data/repos/$REPO_DIR
	logthis "Pulling latest hash commit from $REPO_DIR:$BRANCH"
	REPO_HASHES["$REPO_DIR:$BRANCH"]=`git rev-parse $BRANCH`
done

while true; do
	for row in $(jq -c '.[]' /data/config.json); do
		IN_REPO_URL=`echo $row | jq -r '.input.repo_url'`
		IN_REPO_BRANCH=`echo $row | jq -r '.input.branch'`
		OUT_REPO_URL=`echo $row | jq -r '.output.repo_url'`
		OUT_REPO_BRANCH=`echo $row | jq -r '.output.branch'`
		OUT_DOCKER_FILE=`echo $row | jq -r '.output.docker_file'`

		[[ $IN_REPO_URL =~ $REPO_PATTERN ]]
		IN_REPO_DIR=${BASH_REMATCH[1]}
		if [ ! -d /data/repos/$IN_REPO_DIR ]; then
			logthis "Creating directory /data/repos/$IN_REPO_DIR"
			mkdir /data/repos/$IN_REPO_DIR
		fi
		[[ $OUT_REPO_URL =~ $REPO_PATTERN ]]
		OUT_REPO_DIR=${BASH_REMATCH[1]}

		cd /data/repos
		if [ ! -d /data/repos/$IN_REPO_DIR/.git ]; then
			logthis "Cloning project from $IN_REPO_URL"
			git clone $IN_REPO_URL
		fi
		if [ ! -d /data/repos/$OUT_REPO_DIR/.git ]; then
			logthis "Cloning project from $OUT_REPO_URL"
			git clone $OUT_REPO_URL
		fi

		if [ -z $IN_REPO_BRANCH ] || [ $IN_REPO_BRANCH == 'null' ]; then
			IN_REPO_BRANCH='master'
		fi
		if [ -z $OUT_REPO_BRANCH ] || [ $OUT_REPO_BRANCH == 'null' ]; then
			OUT_REPO_BRANCH='master'
		fi
		if [ -z $OUT_DOCKER_FILE ] || [ $OUT_DOCKER_FILE == 'null' ]; then
			OUT_DOCKER_FILE='Dockerfile'
		fi

		
		logthis "Checking changes in $IN_REPO_DIR:$IN_REPO_BRANCH."
		cd /data/repos/$IN_REPO_DIR
		logthis "Moving to branch $IN_REPO_BRANCH"
		git checkout $IN_REPO_BRANCH
		logthis "Pulling the latest from the repository $IN_REPO_DIR"
		git pull
		logthis "Pulling the latest hash commit from $REPO_DIR:$BRANCH"
		HASH=`git rev-parse $IN_REPO_BRANCH`
		if [ $HASH != ${REPO_HASHES["$IN_REPO_DIR:$IN_REPO_BRANCH"]} ]; then
			logthis "Hashes are different! (new is $HASH, old was ${REPO_HASHES["$IN_REPO_DIR:$IN_REPO_BRANCH"]})"
			if [ ! -f /data/repos/$OUT_REPO_DIR/$OUT_DOCKER_FILE ]; then
				logthis "ERROR: File $OUT_DOCKER_FILE doesn't exist, so we cannot make updates."
			else
				logthis "Updating file $OUT_DOCKER_FILE to set latest commit argument to $HASH"
				cd /data/repos/$OUT_REPO_DIR
				logthis "Moving to branch $OUT_REPO_BRANCH"
				git checkout $OUT_REPO_BRANCH
				logthis "Pulling the latest from the repository $OUT_REPO_DIR"
				git pull
				logthis "Modifying file $OUT_DOCKER_FILE"
				sed -i "s/ARG latest_commit=.*/ARG latest_commit=$HASH/g" $OUT_DOCKER_FILE
				logthis "Adding, committing and pushing the updated file"
				git add $OUT_DOCKER_FILE
				git commit -m "Automatically updated argument hash to $HASH"
				git push
			fi
			REPO_HASHES["$IN_REPO_DIR:$IN_REPO_BRANCH"]=$HASH
		else
			logthis "Hash for $IN_REPO_DIR:$IN_REPO_BRANCH is the same"
		fi
	done

	logthis "Sleeping for $SLEEP_SECONDS seconds."
	sleep $SLEEP_SECONDS &
	wait $!
done
