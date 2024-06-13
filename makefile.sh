#!/bin/bash

export CLUSTER_NAME=${CLUSTER_NAME:-"epinio"}
export TMP_DIR=${TMP_DIR:-"/tmp"}
export DOMAIN=${DOMAIN:-"$(ifconfig -a | grep "inet " | grep -v 127 | awk 'NR==1{print $2}').sslip.io"}
export EPINIO_SERVER_VERSION=${EPINIO_SERVER_VERSION:-"1.11.0"}
export ADM_USR=${ADM_USR:-"admin"}
export ADM_PWD=${ADM_PWD:-"password"}
export ADM_PWD_ENCRYPT=${ADM_PWD_ENCRYPT:-"$(htpasswd -bnBC 10 "" ${ADM_PWD} | tr -d :)"}
export DEV_USR=${DEV_USR:-"dev"}
export DEV_PWD=${DEV_PWD:-"password"}
export DEV_PWD_ENCRYPT=${DEV_PWD_ENCRYPT:-"$(htpasswd -bnBC 10 "" ${DEV_PWD} | tr -d :)"}
export EPINIO_DEPS_BIN=${EPINIO_DEPS_BIN:-"${HOME}/.epinio-install-test"}
export PATH="${PATH}:${EPINIO_DEPS_BIN}"


function check-dependencies() {
    command -v htpasswd > /dev/null || echo "htpasswd - please install"
    command -v docker > /dev/null || echo "docker - please install"
	command -v k3d > /dev/null || echo "k3d - please install"
    command -v kubectl > /dev/null || echo "kubectl - please install"
    command -v helm > /dev/null || echo "helm - please install"
    command -v epinio > /dev/null || echo "htpasswd - please install"
    command -v k9s > /dev/null || echo "k9s - please install"
}

function install-dependencies() {
	mkdir -p ${EPINIO_DEPS_BIN}

	if ! command -v k3d > /dev/null; then
		echo "install k3d ..."
		export K3D_INSTALL_DIR="${EPINIO_DEPS_BIN}"
		export USE_SUDO=false
		curl -sS https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
	fi

	if ! command -v kubectl > /dev/null; then \
		echo "install kubectl ..."
		curl -fsSL -o ${EPINIO_DEPS_BIN}/kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.0/2024-05-12/bin/linux/amd64/kubectl
		chmod +x ${EPINIO_DEPS_BIN}/kubectl
	fi

	if ! command -v helm > /dev/null; then 
		echo "install helm ..."
		export HELM_INSTALL_DIR=${EPINIO_DEPS_BIN}
		export USE_SUDO=false
		curl -sS https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
	fi

	if ! command -v k9s > /dev/null; then
		echo "install k9s ..."
		curl -sS https://webi.sh/k9s | bash
	fi

	if ! command -v epinio > /dev/null; then
		echo "install epinio ..."
		OS=$(echo `uname`|tr '[:upper:]' '[:lower:]')

		ARCH=$(uname -m)
		case $ARCH in
			armv7*) ARCH="armv7";;
			aarch64) ARCH="arm64";;
			x86_64) ARCH="x86_64";;
		esac
		rm -f ${EPINIO_DEPS_BIN}/epinio
		curl -s -o ${EPINIO_DEPS_BIN}/epinio -L https://github.com/epinio/epinio/releases/download/v${EPINIO_SERVER_VERSION}/epinio-${OS}-${ARCH}
		chmod +x ${EPINIO_DEPS_BIN}/epinio
	fi
}

function cleanup-docker() {
	docker rm -f $(docker ps -qa)
	docker system prune -a -f
	docker volume prune -a -f
}

function create-cluster() {
	k3d cluster create ${CLUSTER_NAME} -p '443:443@loadbalancer'
	kubectl rollout status deployment metrics-server -n kube-system --timeout=480s
}

function deploy-cert-manager() {
	kubectl create namespace cert-manager
	helm repo add jetstack https://charts.jetstack.io
	helm repo update
	helm install cert-manager --namespace cert-manager jetstack/cert-manager \
		--set installCRDs=true \
		--set extraArgs[0]=--enable-certificate-owner-ref=true
}

function deploy-epinio() {
	helm repo add epinio https://epinio.github.io/helm-charts
	kubectl rollout status deployment traefik -n kube-system --timeout=480s
	helm install epinio -n epinio --create-namespace --version ${EPINIO_SERVER_VERSION} epinio/epinio \
		--set kubed.operator.repository=mirrored-appscode-kubed \
		--set kubed.operator.registry=rancher \
		--set global.domain=${DOMAIN} \
		--set api.users[0].roles[0]=admin \
		--set api.users[0].username=${ADM_USR} \
		--set api.users[0].passwordBcrypt=${ADM_PWD_ENCRYPT} \
		--set api.users[1].roles[0]=user \
		--set api.users[1].username=${DEV_USR} \
		--set api.users[1].passwordBcrypt=${DEV_PWD_ENCRYPT} \
		# --set minio.enabled=false \
		# --set s3gw.enabled=true \
	# ^^ Use s3gw instead of minio

	kubectl rollout status deployment epinio-server -n epinio --timeout=480s
	
	# Use this fix if helmchart backing service is broken if the version is wrong.
	# kubectl get service.application.epinio -n epinio rabbitmq-dev -o json | jq '.spec.chartVersion="11.2.2"' | kubectl apply -f -
}

function test-ui-login() {
	curl -s -k "https://epinio.${DOMAIN}"
	curl -s -k "https://epinio.${DOMAIN}/pp/v1/epinio/rancher/v3-public/authProviders/local/login" -X POST  --data-raw '{"description":"UI session","responseType":"cookie","username":"admin","password":"password"}'	
}

function test-cli-login() {
	epinio login -u ${ADM_USR} -p ${ADM_PWD}  --trust-ca https://epinio.${DOMAIN}
}

function test-push-app() {
	(
		cd $(mktemp -d) && git clone --depth=1 https://github.com/paketo-buildpacks/samples
		cd samples/python/pip && epinio push --name pip-app --route pip-app.${DOMAIN}
	)
	sleep 5 && curl -k https://pip-app.${DOMAIN}
	echo "****** test epinio app: succeeded"
}

function test-push-app-db() {
	epinio service create mysql-dev mydb --wait
	epinio apps create wordpress
	epinio service bind mydb wordpress
	(
		cd $(mktemp -d) && git clone --depth=1 https://github.com/epinio/example-wordpress && cd example-wordpress
		epinio push -n wordpress -r wordpress.${DOMAIN} -e BP_PHP_VERSION=8.1.x -e BP_PHP_SERVER=nginx -e BP_PHP_WEB_DIR=wordpress \
			-e DB_HOST=$(epinio configurations list | grep mydb | awk '{print $2}') -e SERVICE_NAME=mydb
	)
	sleep 3 && curl -s -k https://wordpress.${DOMAIN} -L | grep 'Error establishing' || true 
	curl -s -k https://wordpress.${DOMAIN} -L | grep 'option value="en_CA"'

	echo "****** test epinio app with backing-sevice: succeeded"

}


function install() {
	check-dependencies

	echo  "****** STEP (1): Create k3d cluster..."
	create-cluster

	echo  "****** STEP (2): Deploy cert-manager into cluster..."
	deploy-cert-manager

	echo "****** STEP (3): Deploy epinio into cluster..."
	deploy-epinio

	echo "****** STEP (4): Verify epinio admin login works..."
	test-ui-login
	test-cli-login

	echo "****** STEP (5): Test epinio cli app push..."
	test-push-app

	echo "****** STEP (6): Test epinio cli app push with DB..."
	test-push-app-db
}


"$*"