package main

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
)

var (
	snsClient   *sns.Client
	snsTopicArn string

	httpClient = &http.Client{
		Timeout: 5 * time.Second,
	}

	connectorBaseURL string
	connectors       = []string{
		"JdbcSinkRoundInteractions",
		"JdbcSinkVanillaInteractions",
	}
)

type Response struct {
	Name      string    `json:"name"`
	Connector Connector `json:"connector"`
	Tasks     []Task    `json:"tasks"`
	Type      string    `json:"type"`
}

type Connector struct {
	State    string `json:"state"`
	WorkerID string `json:"worker_id"`
}

type Task struct {
	ID       int    `json:"id"`
	State    string `json:"state"`
	WorkerID string `json:"worker_id"`
}

func publishSNSMessage(ctx context.Context, subject string, message string) (err error) {
	_, err = snsClient.Publish(ctx, &sns.PublishInput{
		Message:  aws.String(message),
		Subject:  aws.String(subject),
		TopicArn: aws.String(snsTopicArn),
	})
	if err != nil {
		log.Printf("Error publishing message %q to SNS topic %q: %v\n", subject, snsTopicArn, err)
		return err
	}

	return nil
}

func handleRequest(ctx context.Context) error {
	log.Println("Connector Status Lambda function started")

	for _, connector := range connectors {
		endpoint := fmt.Sprintf("%s/connectors/%s/status", connectorBaseURL, connector)

		request, err := http.NewRequest(http.MethodGet, endpoint, nil)
		if err != nil {
			log.Printf("Error while creating create request: %s\n", err)
			return err
		}

		response, err := httpClient.Do(request)
		if err != nil {
			log.Printf("Error fetching connector status: %v\n", err)
			return err
		}
		defer response.Body.Close()

		if response.StatusCode != http.StatusOK {
			alertSubject := fmt.Sprintf("%s Status Alert: Unexpected HTTP Status", connector)
			alertMessage := fmt.Sprintf("The %s status endpoint returned %d status code. Please check the connector and investigate the issue.",
				connector,
				response.StatusCode)

			err := publishSNSMessage(ctx, alertSubject, alertMessage)
			if err != nil {
				log.Printf("Error sending alert to SNS topic: %v\n", err)
				return err
			}
		}

		var connectorStatus Response
		if err := json.NewDecoder(response.Body).Decode(&connectorStatus); err != nil {
			log.Printf("error decoding response body: %v\n", err)
			return err
		}

		for _, task := range connectorStatus.Tasks {
			if task.State != "RUNNING" {
				alertSubject := fmt.Sprintf("Connector: %s, Task ID: %d, Current State: %s", connectorStatus.Name, task.ID, task.State)
				alertMessage := fmt.Sprintf("One or more tasks in '%s' are in a state other than 'RUNNING'.",
					connectorStatus.Name)

				err := publishSNSMessage(ctx, alertSubject, alertMessage)
				if err != nil {
					log.Printf("Error: %v\n", err)
					return err
				}
			}
		}
	}

	log.Println("Connector Status Lambda function finished.")
	return nil
}

func main() {
	connectorBaseURL = os.Getenv("CONNECTOR_BASE_URL")
	if connectorBaseURL == "" {
		log.Fatalf("environment variable CONNECTOR_BASE_URL not set")
	}

	snsTopicArn = os.Getenv("SNS_TOPIC_ARN")
	if snsTopicArn == "" {
		log.Fatalf("environment variable SNS_TOPIC_ARN not set")
	}

	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		log.Fatalf("unable to load SDK config: %v", err)
	}

	snsClient = sns.NewFromConfig(cfg)

	lambda.Start(handleRequest)
}
