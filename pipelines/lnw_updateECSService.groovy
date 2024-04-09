import groovy.json.JsonOutput

def call(cluster, service, taskDefinition, containerDefinition, imageURI, Map<String, String> envVars = [:]) {
    script {
        // Get the latest task definition and write it to a file
        sh "aws ecs describe-task-definition --task-definition ${taskDefinition} > current-task-definition.json"

        def currentImage = sh (
                script: """
                cat current-task-definition.json | jq -r '.taskDefinition.containerDefinitions[] | select(.name == "${containerDefinition}") | .image'
            """,
                returnStdout: true
        ).trim()
        echo "Current image: ${currentImage}"

        echo "New image: ${imageURI}"

        def currentTaskDefinitionARN = sh (
                script: """
                cat current-task-definition.json | jq -r '.taskDefinition.taskDefinitionArn'
            """,
                returnStdout: true
        ).trim()
        echo "Current task definition ARN: ${currentTaskDefinitionARN}"

        // Convert the environment variables map to JSON format
        def envArray = JsonOutput.toJson(envVars.collect { key, value ->
            [name: key, value: value]
        })

        // 1. Update the container image.
        // 2. For each environment variable in the containerDefinition:
        //      - If the name of the environment variable matches a name in the updates array, it updates its value.
        //      - If not, it retains the original value.
        // NOTE: The environment variables must already exist in the task definition.
        sh """
            cat current-task-definition.json | \
            jq --arg image "${imageURI}" --argjson updates '${envArray}' \
            '(.taskDefinition.containerDefinitions[] | select(.name == "${containerDefinition}") | .image) = \$image |
            (.taskDefinition.containerDefinitions[] | select(.name == "${containerDefinition}") | .environment) |= 
            map( . as \$item | 
                (\$updates[] | select(.name == \$item.name)) // \$item
            )' \
            > new-task-definition.json
        """

        // Extract the necessary fields from the JSON file for registering a new task definition
        sh """
            cat new-task-definition.json | jq '.taskDefinition | {family: .family, taskRoleArn: .taskRoleArn, executionRoleArn: .executionRoleArn, networkMode: .networkMode, containerDefinitions: .containerDefinitions, volumes: .volumes, placementConstraints: .placementConstraints, requiresCompatibilities: .requiresCompatibilities, cpu: .cpu, memory: .memory}' > register-task-definition.json
        """

        // Register the new task definition
        sh "aws ecs register-task-definition --cli-input-json file://register-task-definition.json > registered-task-definition.json"
        def newTaskDefinition = sh (
                script: """
                cat registered-task-definition.json | jq -r '.taskDefinition.taskDefinitionArn'
            """,
                returnStdout: true
        ).trim()
        echo "New task definition registered: ${newTaskDefinition}"

        // Update the ECS service with the new task definition
        sh """
            aws ecs update-service --cluster ${cluster} --service ${service} --task-definition ${newTaskDefinition}
        """

        // Wait for the service to become stable and handle errors
        try {
            sh "aws ecs wait services-stable --cluster ${cluster} --services ${service}"
        } catch (Exception e) {
            echo "Service did not stabilize. Fetching error details from the failed task."

            // Fetch the most recent task ARN that failed
            def failedTaskArn = sh(
                    script: """
                aws ecs list-tasks --cluster ${cluster} --service-name ${service} --desired-status STOPPED --query 'taskArns[0]' --output text
                """,
                    returnStdout: true
            ).trim()

            if (failedTaskArn && failedTaskArn != "None") {
                // Retrieve the details of the failed task, including error messages
                def taskDetails = sh(
                        script: """
                    aws ecs describe-tasks --cluster ${cluster} --tasks ${failedTaskArn} --query 'tasks[0].stoppedReason' --output text
                    """,
                        returnStdout: true
                ).trim()

                echo "Details of the failed task: ${taskDetails}"
            } else {
                echo "No failed task found."
            }
        }
    }
}
