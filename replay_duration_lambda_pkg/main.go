package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/cloudwatch"
	"github.com/aws/aws-sdk-go/service/secretsmanager"
	_ "github.com/lib/pq"
	"log"
	"os"
	"time"
)

const (
	namespace  string = "ReplayServiceCustomMetrics"
	metricName string = "response.time.per.roundId"
)

func calcDurationSecs(createdAt, insertedAt time.Time) float64 {
	return insertedAt.Sub(createdAt).Seconds()
}

func putMetricInCloudWatch(cw *cloudwatch.CloudWatch, value float64, roundID int64) error {
	var lastErr error
	for i := 0; i < 3; i++ { // Retry up to 3 times
		_, err := cw.PutMetricDataWithContext(context.TODO(), &cloudwatch.PutMetricDataInput{
			Namespace: aws.String(namespace),
			MetricData: []*cloudwatch.MetricDatum{
				{
					MetricName: aws.String(metricName),
					Value:      aws.Float64(value),
					Unit:       aws.String("Seconds"),
				},
			},
		})
		if err == nil {
			log.Printf("Metric '%s':'%f' for RoundId '%d' sent to CloudWatch.\n", metricName, value, roundID)
			return nil
		}
		lastErr = err
		time.Sleep(1 * time.Second) // Wait for a second before retrying
	}
	log.Printf("Error sending metric to CloudWatch after retries: %v\n", lastErr)
	return lastErr
}

func retrieveSecrets(sc *secretsmanager.SecretsManager, secretArn string) (string, error) {
	var lastErr error
	for i := 0; i < 3; i++ {
		// Retry up to 3 times
		log.Printf("Call GetSecretValue: %d\n", i)
		secretValue, err := sc.GetSecretValue(&secretsmanager.GetSecretValueInput{
			SecretId: aws.String(secretArn),
		})
		if err == nil {
			log.Printf("Secret String: %s\n", *secretValue.SecretString)
			// Decode the SecretString JSON
			var secretMap map[string]string
			if err := json.Unmarshal([]byte(*secretValue.SecretString), &secretMap); err != nil {
				return "", err
			}
			// Retrieve the password from the decoded JSON
			password, ok := secretMap["password"]
			if !ok {
				log.Printf("Password not found in SecretString")
				return "", errors.New("password not found in SecretString")
			}
			return password, nil
		}
		log.Printf("Error from secrets manager: %s\n", err)
		lastErr = err
		time.Sleep(1 * time.Second) // Wait for a second before retrying
	}

	return "", lastErr
}

func HandleRequest(ctx context.Context) (string, error) {
	log.Println("Lambda function started.")

	dbHost := os.Getenv("DB_HOST")
	dbPort := os.Getenv("DB_PORT")
	dbName := os.Getenv("DB_NAME")
	dbUsername := os.Getenv("DB_USERNAME")
	databaseSecretArn := os.Getenv("DATABASE_SECRET_ARN")

	log.Println("Retrieved environment variables.")

	// Create a Secrets Manager client
	sess, err := session.NewSession()
	if err != nil {
		log.Printf("Error creating AWS session: %v\n", err)
		return "", err
	}
	sc := secretsmanager.New(sess)

	log.Printf("Created session with Secrets Manager")

	// Retrieve the database password from Secrets Manager
	dbPassword, err := retrieveSecrets(sc, databaseSecretArn)
	if err != nil {
		log.Printf("Error while retrieving DB password: %v\n", err)
		return "", nil
	}

	log.Printf("Retrieved DB password from Secrets Manager")

	// Connect to the database
	psqlInfo := fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=disable",
		dbHost, dbPort, dbName, dbUsername, dbPassword)
	db, err := sql.Open("postgres", psqlInfo)
	if err != nil {
		log.Printf("Error opening database: %v\n", err)
		return "", err
	}

	defer db.Close()

	log.Println("Connected to the database")

	// Define the SQL query
	query := `SELECT created_at, inserted_at, round_id FROM round_interactions WHERE inserted_at >= now() - INTERVAL '30 minutes';`

	// Execute the query
	rows, err := db.Query(query)
	if err != nil {
		log.Printf("Error executing query: %v", err)
		return "", err
	}
	defer rows.Close()

	cw := cloudwatch.New(sess)

	for rows.Next() {
		var createdAt, insertedAt time.Time
		var roundID int64
		err := rows.Scan(&createdAt, &insertedAt, &roundID)
		if err != nil {
			log.Printf("Error scanning row: %v", err)
			return "", err // Return an error if the row fails to scan
		}

		duration := calcDurationSecs(createdAt, insertedAt)
		log.Printf("Duration for RoundID %d: %f seconds\n", roundID, duration)

		if err := putMetricInCloudWatch(cw, duration, roundID); err != nil {
			log.Printf("Error sending metric to CloudWatch for RoundID %d: %v", roundID, err)
		}
	}

	log.Println("Lambda function finished.")
	return "Success", nil
}

func main() {
	lambda.Start(HandleRequest)
}
