@Library('pipelines@master') _

def determinedEnv = ""

pipeline {
    agent { label 'aws-slave || docker-slave' }

    tools {
        terraform "1.5.7"
    }

    options {
        timestamps()
        ansiColor('xterm')
    }

    environment {
        APPLY = false
        location = "./"
        instance = "fft"
        ou = "XXXXXX"
        account = "XXXXXX"
        aws_credentials = "XXXXXX"
        cloudflare_credential = "LZ_CLOUDFLARE_FFT_NYXOP_NET"
        grafana_credential = "GRAFANA_AUTH"
        aws_region = "eu-central-1"
        AWS_ROLE = "update_db_users"
    }

    stages {
        stage('FindBuildInitiator & SlackNotifyBuildStart') {
            steps {
                script {
                    sg_slackNotifyBuildStart([slackCredentialID: 'sgdigitaljackpotapps', slackChannel: 'gdm-platform-apps-cicd', slackChannelReleases: 'gdm-platform-apps-cicd-releases'])
                }
            }
        }
        stage('Determine Environment') {
            steps {
                script {
                    determinedEnv = (env.BRANCH_NAME == 'master') ? 'prod' : 'dev'
                    env.ENV = determinedEnv
                    // Dynamically set AWS_ACCOUNT
                    env.AWS_ACCOUNT = (env.BRANCH_NAME == 'master') ? '346245435745' : '345234652456'
                    echo "ENV = ${env.ENV}"
                    echo "AWS_ACCOUNT = ${env.AWS_ACCOUNT}"
                }
            }
        }

        stage('Build and Zip Lambda Function') {
            steps {
                script {
                    def goArch = 'amd64'
                    def goOs = 'linux'
                    def outputBinary = 'main'

                    def buildAndZipLambda = { zipFile, sourceDir ->
                        dir(sourceDir) {
                            // Download dependencies
                            sh "go mod tidy"
                            // Build the Go binary for Amazon Linux architecture
                            sh "env GOARCH=${goArch} GOOS=${goOs} go build -o ${outputBinary}"
                            // Zip the executable
                            sh "zip ${zipFile} ${outputBinary}"
                        }
                    }
                    //build and zip replay_duration_lambda_pkg
                    buildAndZipLambda('package.zip', 'replay_duration_lambda_pkg')
                    //build and zip connector_status_lambda_pkg
                    buildAndZipLambda('connector_package.zip', 'connector_status_lambda_pkg')
                }
            }
        }

        stage('Init') {
            steps {
                sh "env"
                dir("${location}") {
                    withAWS(credentials: "${aws_credentials}", region: "${aws_region}") {
                        withCredentials([string(credentialsId: "${cloudflare_credential}", variable: 'CLOUDFLARE_API_TOKEN')]) {
                            withCredentials([string(credentialsId: "${grafana_credential}", variable: 'GRAFANA_AUTH')]) {
                                sh "make -f tools/Makefile init INSTANCE=${instance} AWS_REGION=eu-west-1 OU=${ou} ACCOUNT=${account} ENV=${ENV}"
                            }
                        }
                    }
                }
            }
        }

        stage('SSM tunnel') {
            steps {
                dir("${location}") {
                    withAWS(credentials: "${aws_credentials}", region: "${aws_region}") {
                        withAWS(roleAccount: "${AWS_ACCOUNT}", role: "${AWS_ROLE}", region: "${aws_region}") {
                            script {
                                // Retrieve the Instance ID of the Bastion Host
                                def bastionInstanceId = sh(script: "aws ec2 describe-instances --filters 'Name=tag:Name,Values=bastionserver-0-${ENV}-eu-central-1a-fft' --query 'Reservations[*].Instances[*].InstanceId' --output text", returnStdout: true).trim()

                                // Retrieve the RDS Endpoint
                                def rdsEndpoint = sh(script: "aws rds describe-db-instances --db-instance-identifier replayservice-XXXXX-${ENV}-db --query 'DBInstances[*].Endpoint.Address' --output text", returnStdout: true).trim()

                                // Start SSM Session
                                sh "aws --region=eu-central-1 ssm start-session --target ${bastionInstanceId} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"${rdsEndpoint}\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"5450\"]}' &"
                            }
                        }
                    }
                }
            }
        }


        stage('Plan') {
            steps {
                dir("${location}") {
                    withAWS(credentials: "${aws_credentials}", region: "${aws_region}") {
                        withCredentials([string(credentialsId: "${cloudflare_credential}", variable: 'CLOUDFLARE_API_TOKEN')]) {
                            withCredentials([string(credentialsId: "${grafana_credential}", variable: 'GRAFANA_AUTH')]) {
                                sh "make -f tools/Makefile plan INSTANCE=${instance} AWS_REGION=${aws_region} OU=${ou} ACCOUNT=${account} ENV=${ENV}"
                            }
                        }
                    }
                }
            }
        }

        stage('Approve') {
            when {
                anyOf {
                    branch 'dev'
                    branch 'master'
                }
            }
            steps {
                script {
                    try {
                        timeout(time:20, unit:'MINUTES') {
                            APPROVE_PLAN = input message: 'Approve plan?', ok: 'Continue',
                                    parameters: [choice(name: 'APPROVE_PLAN', choices: 'YES\nNO', description: 'Approve plan?')]
                            echo "APPROVE_PLAN = ${APPROVE_PLAN}"

                            if ("${APPROVE_PLAN}" == 'YES') {
                                echo "Approving plan"
                                APPLY = true
                            } else {
                                APPLY = false
                            }
                        }
                    } catch (error) {
                        APPLY = false
                        echo 'Plan timeout, skipping apply'
                    }
                }
            }
        }

        stage('Apply') {
            when {
                allOf {
                    expression { APPLY == true }

                    anyOf {
                        branch 'dev'
                        branch 'master'
                        tag pattern: /^[a-z]{3}-stg-(?:[0-9]+\.){2}[0-9]+$/, comparator: "REGEXP"
                        tag pattern: /^[a-z]{3}-(?:[0-9]+\.){2}[0-9]+$/, comparator: "REGEXP"
                    }
                }
            }
            steps {
                withAWS(credentials: "${aws_credentials}", region: "${aws_region}") {
                    withCredentials([string(credentialsId: "${cloudflare_credential}", variable: 'CLOUDFLARE_API_TOKEN')]) {
                        withCredentials([string(credentialsId: "${grafana_credential}", variable: 'GRAFANA_AUTH')]) {
                            sh "make -f tools/Makefile apply APPROVE=yes INSTANCE=${instance} AWS_REGION=${aws_region} OU=${ou} ACCOUNT=${account} ENV=${ENV}"
                        }
                    }
                }
            }
            post {
                failure {
                    script { FAILURE_STAGE = 'Apply' }
                }
            }
        }
    }
    post {
        always {
            script {
                sg_postAlways([slackCredentialID: 'sgdigitaljackpotapps', slackChannel: 'gdm-platform-apps-cicd', slackChannelReleases: 'gdm-platform-apps-cicd-releases'])
            }
        }
    }
}