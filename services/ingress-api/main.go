package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/redis/go-redis/v9"
)

// Global context and Redis client instance
var ctx = context.Background()

type SQSClient struct {
	Client   *sqs.Client
	QueueUrl string
}

type application struct {
	rdb *redis.Client
	sqs *SQSClient
}

// SecurityEvent represents the structure of our inbound e-commerce payload
type SecurityEvent struct {
	TransactionID string `json:"transaction_id"`
	UserID        string `json:"user_id"`
	Action        string `json:"action"` // e.g., "checkout_fail", "login_success"
	IPAddress     string `json:"ip_address"`
	Status        string `json:"status"`
	Timestamp     string `json:"timestamp"`
}

func (app application) IsUserBlocked(ctx context.Context, userKey string) (bool, error) {
	redisKey := fmt.Sprintf("block:user_id:%s", userKey)

	// Exists returns the number of keys found (0 or 1 in this case)
	count, err := app.rdb.Exists(ctx, redisKey).Result()
	if err != nil {
		return false, fmt.Errorf("failed to check redis key: %w", err)
	}

	// If count is greater than 0, the key is present
	return count > 0, nil
}

func (app application) IsIPBlocked(ctx context.Context, ip string) (bool, error) {
	redisKey := fmt.Sprintf("block:ip:%s", ip)

	// Exists returns the number of keys found (0 or 1 in this case)
	count, err := app.rdb.Exists(ctx, redisKey).Result()
	if err != nil {
		return false, fmt.Errorf("failed to check redis key: %w", err)
	}

	// If count is greater than 0, the key is present
	return count > 0, nil
}

func initSQS() (*SQSClient, error) {
	queueURL := os.Getenv("SQS_QUEUE_URL")
	if queueURL == "" {
		return nil, fmt.Errorf("SQS_QUEUE_URL environment variable is not set")
	}

	// Loads AWS configuration automatically from the Lambda IAM runtime execution role
	cfg, err := config.LoadDefaultConfig(context.Background(),
		config.WithRegion("us-east-1"),
	)

	if err != nil {
		return nil, fmt.Errorf("unable to load SDK config: %w", err)
	}

	return &SQSClient{
		Client:   sqs.NewFromConfig(cfg),
		QueueUrl: queueURL,
	}, nil
}

func (app application) PushToQueue(ctx context.Context, messageBody string) error {
	input := &sqs.SendMessageInput{
		QueueUrl:    &app.sqs.QueueUrl,
		MessageBody: &messageBody,
		// If you use the FIFO queue, you must also pass MessageGroupId here:
		// MessageGroupId: aws.String("ecommerce-orders"),
	}

	_, err := app.sqs.Client.SendMessage(ctx, input)
	if err != nil {
		return fmt.Errorf("failed to route message to SQS: %w", err)
	}

	return nil
}

func initRedis() (*redis.Client, error) {
	redisEndpoint := os.Getenv("REDIS_ENDPOINT") // e.g., "ecommerce-rate-limiter.xxxxxx.use1.cache.amazonaws.com:6379"
	if redisEndpoint == "" {
		return nil, fmt.Errorf("REDIS_ENDPOINT environment variable is not set")
	}

	// Initialize the Redis client connection pool pointing to our active port
	rdb := redis.NewClient(&redis.Options{
		Addr:     redisEndpoint,
		Password: "",
		DB:       0,
		TLSConfig: &tls.Config{
			MinVersion: tls.VersionTLS12,
		},
	})

	err := rdb.Ping(context.Background()).Err()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Redis endpoint: %w", err)
	}

	return rdb, nil
}

func (app application) handleLambdaRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var event SecurityEvent

	log.Printf("DEBUG: ->Starting request processing...")
	log.Printf("DEBUG: Raw request body: %s", request.Body)

	err := json.Unmarshal([]byte(request.Body), &event)
	if err != nil {
		log.Printf("ERROR: JSON Unmarshal failed: %v", err)
		return events.APIGatewayProxyResponse{StatusCode: http.StatusBadRequest, Body: `{"error":"Invalid JSON payload"}`}, nil
	}

	log.Printf("DEBUG: Just did unmarshalling")

	var messageBytes []byte
	_, err = strconv.ParseInt(event.Timestamp, 10, 64)

	if err != nil || event.Timestamp == "" {
		// Timestamp was missing or invalid; update struct and marshal the modified version
		event.Timestamp = strconv.FormatInt(time.Now().Unix(), 10)
		messageBytes, err = json.Marshal(event)
		if err != nil {
			log.Printf("ERROR: JSON Marshal failed: %v", err)
			return events.APIGatewayProxyResponse{StatusCode: http.StatusInternalServerError, Body: `{"error":"Internal server error"}`}, nil
		}
	} else {
		// Timestamp was valid, safely reuse the raw request body payload
		messageBytes = []byte(request.Body)
	}

	userBlocked, err := app.IsUserBlocked(ctx, event.UserID)
	if err != nil {
		return events.APIGatewayProxyResponse{StatusCode: http.StatusInternalServerError, Body: `{"error":"Database error"}`}, nil
	}
	log.Printf("DEBUG: Checked if user is blocked")

	ipBlocked, err := app.IsIPBlocked(ctx, event.IPAddress)
	if err != nil {
		return events.APIGatewayProxyResponse{StatusCode: http.StatusInternalServerError, Body: `{"error":"Database error"}`}, nil
	}

	if userBlocked || ipBlocked {
		log.Printf("DEBUG: It's blocked, sending to redis blocked")
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusTooManyRequests,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       `{"error":"Request rejected due to temporary security block"}`,
		}, nil
	}

	log.Printf("DEBUG: Pushing to SQS queue")
	err = app.PushToQueue(ctx, string(messageBytes))
	if err != nil {
		return events.APIGatewayProxyResponse{StatusCode: http.StatusInternalServerError, Body: `{"error":"Queue error"}`}, nil
	}

	log.Printf("DEBUG: All done")
	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusAccepted,
		Body:       `{"status":"event_queued"}`,
	}, nil
}

func main() {
	rdb, err := initRedis()

	if err != nil {
		//redisEndpoint := os.Getenv("REDIS_ENDPOINT")
		//log.Printf("CRITICAL: Redis Connection Failed. Error: %v | Endpoint: %s", err, redisEndpoint)
		panic(fmt.Sprintf("CRITICAL_REDIS_ERROR: %v", err))
	}

	sqs, err := initSQS()

	if err != nil {
		panic(fmt.Sprintf("CRITICAL_SQS_ERROR: %v", err))
	}

	app := &application{
		rdb: rdb,
		sqs: sqs,
	}

	lambda.Start(app.handleLambdaRequest)

}
