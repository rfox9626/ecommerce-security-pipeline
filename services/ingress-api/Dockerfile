# ---------------------------------------------------------------------
# Stage 1: Build the Go binary
# ---------------------------------------------------------------------
FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -tags lambda.norpc -o bootstrap main.go

# ---------------------------------------------------------------------
# Stage 2: Final Runtime Image
# ---------------------------------------------------------------------
FROM public.ecr.aws/lambda/provided:al2023

# Copy the bootstrap binary directly to the path al2023 expects
COPY --from=builder /app/bootstrap /var/runtime/bootstrap

WORKDIR ${LAMBDA_TASK_ROOT}

CMD [ "bootstrap" ]
