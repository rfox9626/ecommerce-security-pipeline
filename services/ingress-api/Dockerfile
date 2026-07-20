# ---------------------------------------------------------------------
# Stage 1: Build the Go binary
# ---------------------------------------------------------------------
FROM golang:1.24-alpine AS builder

# Set the working directory inside the container
WORKDIR /app

# Copy dependency files and download Go modules
COPY go.mod go.sum ./
RUN go mod download

# Copy the remaining application source code
COPY . .

# Build a statically linked binary optimized for AWS Lambda custom runtimes
# - CGO_ENABLED=0 ensures the binary has no dynamic C library dependencies
# - GOOS=linux targets the Linux operating system required by Lambda
# - tags lambda.norpc builds a lightweight binary omitting the legacy RPC layer
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -tags lambda.norpc -o bootstrap main.go

# ---------------------------------------------------------------------
# Stage 2: Final Runtime Image
# ---------------------------------------------------------------------
FROM public.ecr.aws/lambda/provided:al2023
COPY --from=builder /app/bootstrap /var/task/bootstrap

# Explicitly tell the container where to run from
WORKDIR ${LAMBDA_TASK_ROOT}

# Set the entry point using the absolute path
ENTRYPOINT [ "/var/task/bootstrap" ]
