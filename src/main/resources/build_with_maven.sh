#!/bin/bash -ex

function usage() {

	echo "Usage: $0 -i initiator -a arn -h hash -b bucket -m (RELEASE | SNAPSHOT) -x (0 | 1) -e (0 | 1)"
}

function getOptions() {

	while getopts ":i:a:h:b:m:x:e:" option; do
		case "${option}"
			in
				i) INITIATOR=${OPTARG};;
				a) ARN=${OPTARG};;
				h) HASH=${OPTARG};;
				b) BUCKET=${OPTARG};;
				m) MODE=${OPTARG};;
				x) X_DEBUG=${OPTARG};;
				e) E_DEBUG=${OPTARG};;
				*) echo Invalid option ${OPTARG}
				   usage
				   exit -1;;
		esac
	done
	shift "$((OPTIND-1))"

	if [ $# -gt 0 ]; then
		echo Invalid arguments left $*
		usage
		exit -1
	fi
}

function getAndSetGitCredentials() {

    ACCOUNT=$(echo $ARN | cut -d : -f 5)
    [ $INITIATOR == "codepipeline" ] && GIT_USERNAME=${INITIATOR}-at-$ACCOUNT ||  GIT_USERNAME=${INITIATOR}+1-at-$ACCOUNT
    GIT_PASSWORD_KEY=GIT_PASSWORD_${INITIATOR}
    GIT_PASSWORD=$(aws ssm get-parameters --names $GIT_PASSWORD_KEY --query "Parameters[0].{Value:Value}" | grep Value | cut -f 2 -d : | tr -d '"' | tr -d ' ')
    [ -z "$GIT_PASSWORD" ] && echo "Empty GIT PASSWORD" && exit -1 || :
}

function cloneRepository() {

	rm -rf * .[^.]*
	REPO=$(echo $ARN | cut -f 6 -d : | cut -f 2 -d /)
	git clone https://$GIT_USERNAME:$GIT_PASSWORD@git-codecommit.us-east-1.amazonaws.com/v1/repos/$REPO .
}

function getAndSetCommitMessage() {

	COMMIT_MESSAGE=$(git log --format=%B -n 1 $HASH)
}

function getAndSetBranch() {

    REFS=$(git describe --all $HASH)
	if [[ $REFS = *master* ]]; then
	    BRANCH=master
	else
	    BRANCH=$(echo $REFS | cut -f 3 -d /)
        [ -z "$BRANCH" ] && echo "Empty branch" && exit -1 || :
	fi
	git checkout $BRANCH        
}

function setGitIdentity() {

	git config user.name $INITIATOR
	git config user.email ${INITIATOR}@azlits.com
}

function checkOptions() {

	# Check initiator
	[ -z "$INITIATOR" ] && echo "Empty initiator" && usage && exit -1 || :
	if [[ $INITIATOR = *codepipeline* ]]; then
		INITIATOR=codepipeline
		getAndSetGitCredentials
		cloneRepository
		getAndSetCommitMessage
    fi

	# Check arn
	[ -z "$ARN" ] && echo "Empty arn" && usage && exit -1 || :

	# Check hash
	[ -z "$HASH" ] && echo "Empty hash" && usage && exit -1 || :
	if [ "$MODE" == "RELEASE" ]; then
		getAndSetBranch
    fi

	# Check bucket
	[ -z "$BUCKET" ] && echo "Empty bucket" && usage && exit -1 || :

	# Check mode
    if [ $INITIATOR == "codepipeline" ]; then
		[[ $COMMIT_MESSAGE =~ MODE=([A-Z]*) ]] && MODE="${BASH_REMATCH[1]}" || :
	fi
	[ -z "$MODE" ] && echo "Empty mode" && usage && exit -1 || :
	[ $MODE != "SNAPSHOT" -a $MODE != "RELEASE" ] && echo "Invalid mode" && usage && exit -1 || :

	# Check GIT PASSWORD
	if [ "$MODE" == "RELEASE" ]; then
		if [ $INITIATOR != "codepipeline" ]; then
			getAndSetGitCredentials
		fi
		setGitIdentity
    fi

	# Check x debug
    if [ $INITIATOR == "codepipeline" ]; then
       [[ $COMMIT_MESSAGE =~ X_DEBUG=([0|1]) ]] && X_DEBUG="${BASH_REMATCH[1]}" || :
    fi
	[ -z "$X_DEBUG" ] && echo "Empty x debug" && usage && exit -1 || :
    [ $X_DEBUG != "0" -a $X_DEBUG != "1" ] && echo "Invalid x debug" && usage && exit -1 || :

	# Check e debug
    if [ $INITIATOR == "codepipeline" ]; then
        [[ $COMMIT_MESSAGE =~ E_DEBUG=([0|1]) ]] && E_DEBUG="${BASH_REMATCH[1]}" || :
    fi
	[ -z "$E_DEBUG" ] && echo "Empty e debug" && usage && exit -1 || :
	[ $E_DEBUG != "0" -a $E_DEBUG != "1" ] && echo "Invalid e debug" && usage && exit -1 || :

	# Check ID
	ID=$(aws iam list-access-keys --user-name $INITIATOR | grep AccessKeyId | cut -f 2 -d : | tr -d '"' | tr -d ' ')
	[ -z "$ID" ] && echo "Empty ID" && exit -1 || :
}

function getSecret() {

    SECRET_KEY=secret_${INITIATOR}
    SECRET_PASSWORD=$(aws ssm get-parameters --names $SECRET_KEY --with-decryption --query "Parameters[0].{Value:Value}" | grep Value | cut -f 2 -d : | tr -d '"' | tr -d ' ')
}

function makeMavenCommand() {

	MAVEN_BUCKET=-Dmaven.build.bucket.name=$BUCKET
	MAVEN_ID=-Dmaven.repo.id=$ID
	getSecret
	MAVEN_SECRET=-Dmaven.repo.secret=$SECRET_PASSWORD
	MAVEN_OPTS="$MAVEN_OPTS $MAVEN_BUCKET $MAVEN_ID $MAVEN_SECRET"
	export MAVEN_OPTS
    export AWS_ACCESS_KEY_ID=$ID
    export AWS_SECRET_KEY=$SECRET_PASSWORD
 	[ $X_DEBUG -eq 1 ] && MAVEN_X_DEBUG=-X || MAVEN_X_DEBUG=""
	[ $E_DEBUG -eq 1 ] && MAVEN_E_DEBUG=-e || MAVEN_E_DEBUG=""

	if [ "$MODE" == "RELEASE" ]; then
		MAVEN_GIT_USER=-Dusername=$GIT_USERNAME
		MAVEN_GIT_PASSWORD=-Dpassword=$GIT_PASSWORD
		MAVEN_COMMAND="mvn $MAVEN_X_DEBUG $MAVEN_E_DEBUG $MAVEN_OPTS $MAVEN_GIT_USER $MAVEN_GIT_PASSWORD release:prepare release:perform --batch-mode"
	else
		MAVEN_COMMAND="mvn $MAVEN_X_DEBUG $MAVEN_E_DEBUG $MAVEN_OPTS deploy"
	fi
}

function main() {

	getOptions $*
	checkOptions
	makeMavenCommand

	$MAVEN_COMMAND
}

main $*
